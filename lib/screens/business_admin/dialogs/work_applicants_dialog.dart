// lib/screens/business_admin/dialogs/work_applicants_dialog.dart
// 업무별 지원자 관리 다이얼로그 - 개선된 버전

import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
// [BULK-DISPATCH] 서버가 중복 발송을 막은 `already-exists` 를 실패와 구별하려면
//   CF 예외 타입이 필요하다.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/business_model.dart';
import '../../../models/core/employment_contract_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/user_model.dart';
import '../../../services/contract_service.dart';
import '../../../services/business_posting_readiness.dart';
import '../../../services/firestore_service.dart';
import '../../../services/invite_save_verifier.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/person_label.dart';
import '../../../utils/contract_attendance_gate.dart';
import '../../../utils/loading_state_mixin.dart';
import '../../../utils/posting_readiness_reason.dart';
import '../../../widgets/dialogs/application_policy_acknowledge_sheet.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/text_layout.dart';
import '../../../utils/dialog_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../widgets/dialogs/alternative_work_offer_sheet.dart';
import '../../../widgets/dialogs/confirmed_reassignment_sheet.dart';
import '../../../models/core/confirmed_reassignment_proposal.dart';
import '../../../services/confirmed_reassignment_service.dart';
import '../../../widgets/dialogs/contract_template_selector_dialog.dart';
import '../../common/settings_screen.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../models/ui/invite_capacity_state.dart';
// [ISG2-REFRESH] 초대 결과 → 전파·재조회 판단 한 곳.
import '../../../models/ui/invite_refresh_outcome.dart';
import '../../../utils/action_guard.dart';
import '../../../utils/close_state_utils.dart';
import 'invite_method_sheet.dart';
import 'available_workers_bottom_sheet.dart';
import 'invite_worker_dialog.dart';
import 'work_applicants_reads.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/adaptive_action_row.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../utils/id_card_helper.dart';
import 'fixed_worker_management_dialog.dart';
import '../../../utils/format_helper.dart';
// trust_score_helper: 신뢰도 점수 시스템 제거 (5A.2A)
import '../../../utils/week_helper.dart';
import '../../../models/core/attendance_model.dart';
import '../../../screens/contract/contract_sign_screen.dart' show ContractTemplateWidget;
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../models/core/business_member_model.dart';
// [R7-P1-2 DEVICE.1E.1] 화면에서 분리한 판정들 — 실행으로 증명하기 위해서다.
import '../../../models/ui/capacity_load_state.dart';
import '../../../models/ui/work_capacity_reading.dart';
import '../../../utils/applicant_load_outcome.dart';
import '../../../utils/staffing_relation.dart';
import '../../../widgets/admin/applicant_row_surface.dart';
import '../../../widgets/admin/capacity_summary_text.dart';
import '../../../widgets/admin/contract_attendance_unknown_notice.dart';
import '../../../widgets/admin/invite_roster_row.dart';
import '../../../models/ui/work_applicant_split.dart';
import '../../../utils/staffing_clock.dart';

/// [BULK-DISPATCH] 서버가 끝까지 처리했는지 **알 수 없는** CF 오류 코드.
///
///   이 코드들에서는 계약서가 커밋됐을 수도, 안 됐을 수도 있다. 지원서 상태를
///   되돌리면 커밋된 쪽에서 계약서와 지원서가 어긋난다 — 확정을 유지하고
///   관리자에게 "확인 필요"로 말한 뒤 목록을 다시 읽는다.
const Set<String> _indeterminateCfCodes = {
  'deadline-exceeded',
  'unavailable',
  'internal',
  'cancelled',
  'aborted',
};

/// 다이얼로그 결과
class WorkApplicantsDialogResult {
  final bool hasChanges;

  /// [ISG2-REFRESH] 이 변경이 **Home 의 진실**까지 바꾸는가.
  ///
  ///   Home 의 인력 현황은 `confirmed` 기준이다. 초대는 `대기` 만 올리므로
  ///   Home 숫자를 바꾸지 않는다 — 그런데 Home full refresh 는
  ///   2 callable + 약 4N query 다(`WorkforceController.notifyDataChanged`
  ///   주석의 기록된 결정). 그래서 "카드를 다시 그려야 한다"와
  ///   "Home 에 알려야 한다"를 한 깃발로 묶지 않는다.
  ///
  ///   초대만 있었다면 `hasChanges = true`, `homeRelevant = false`.
  final bool homeRelevant;
  final Set<String> affectedTOIds;  // 충돌로 영향받은 다른 TO ID

  const WorkApplicantsDialogResult({
    this.hasChanges = false,
    this.homeRelevant = false,
    this.affectedTOIds = const <String>{},
  });
}

/// 업무별 지원자 관리 다이얼로그 - 개선된 버전
class WorkApplicantsDialog extends StatefulWidget {
  final WorkDetailModel? work;  // null = 전체 업무 그룹 모드
  final TOItem toItem;
  final VoidCallback onChanged;
  /// 알림 딥링크에서 특정 지원자를 바로 강조 표시할 때 전달. null이면 일반 목록 표시.
  final String? initialApplicationId;
  /// 알림 딥링크에서 slot이 없을 때 헤더에 표시할 날짜. slot?.date가 우선한다.
  final DateTime? initialDate;
  /// [BIZCTX-PATCH] 알림 딥링크 경로에서 target business B의 실제 권한 주입.
  /// null → 기존 UserProvider.can() 동작 유지 (non-notification 경로 / BUSINESS_ADMIN).
  /// non-null → canManageTo UI guard를 이 객체 기준으로 평가한다 (SUB_ADMIN cross-biz 대응).
  final MemberPermissions? targetPermissions;

  const WorkApplicantsDialog({
    super.key,
    this.work,
    required this.toItem,
    required this.onChanged,
    this.initialApplicationId,
    this.initialDate,
    this.targetPermissions,
  });

  @override
  State<WorkApplicantsDialog> createState() => _WorkApplicantsDialogState();
}

/// [E1-FIXTURE-CLOCK] 이 창의 "지금" — 판정마다 같은 시계(`StaffingClock`)를 쓴다.
DateTime _workApplicantsNow() => StaffingClock.now();

class _WorkApplicantsDialogState extends State<WorkApplicantsDialog>
    with LoadingStateMixin {
  final FirestoreService _firestoreService = FirestoreService();

  /// [E2-INVITED-SEAT] 이 창의 읽기 — 운영은 production, 테스트만 debugOverride.
  late final WorkApplicantsReads _reads = WorkApplicantsReads.debugOverride ??
      WorkApplicantsReads.production(_firestoreService);

  List<Map<String, dynamic>> _applicants = [];
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _confirmed = [];
  /// [R7-P1-2 DEVICE.1E] 결정까지 끝난 근무 관계 — 이력으로 남는다.
  List<Map<String, dynamic>> _ended = [];
  /// [R7-P1-2 DEVICE.1E.1] 기간은 지났는데 연장/종료 결정이 남았다 — 할 일이 있다.
  List<Map<String, dynamic>> _decisionPending = [];
  /// [R7-P1-2 DEVICE.1E.1] 자리를 반납했다(대체충원). 관계가 끝난 것은 아니다.
  List<Map<String, dynamic>> _released = [];
  // 통계 계산용 전체 앱 목록 (_loadApplicants에서 캐시, _updateLocalStats에서 재사용)
  List<ApplicationModel> _allApplications = [];

  /// [E2-INVITED-SEAT] 아직 응답하지 않은 초대(INVITED) — `{application, user}`.
  ///
  ///   지원(`_pending`)과 합치지 않는다. 지원은 근로자가 표시한 관심이고 초대는
  ///   관리자가 먼저 보낸 제안이라 다음 행동이 다르다(초대에는 승인 버튼이 없다).
  ///   예전에는 이 화면이 INVITED 를 버려 초대만 있는 업무를 열면
  ///   `지원자가 없습니다` 였다 — 날짜별 명단은 같은 초대를 `초대 중` 으로 보였다.
  ///   행은 명단 조회가 **이미 받은** 지원서에서 고른다(추가 조회 없음).
  List<Map<String, dynamic>> _invites = [];

  final Set<String> _selectedIds = {};
  final Set<String> _starredIds = <String>{};
  bool _selectAll = false;
  bool _isBatchMode = false;
  
  // 신분증 상태 맵
  Map<String, String> _idCardStatusMap = {};
  // ⭐ 변경 여부 추적
  bool _hasChanges = false;

  /// [ISG2-REFRESH] **초대만** 바꾼 변경.
  ///
  ///   초대는 `대기` 를 올리므로 이 카드는 다시 그려야 한다. 그러나 Home 의
  ///   인력 현황은 `confirmed` 기준이라 바뀌지 않는다 — 기록된 결정대로
  ///   Home full refresh 를 깨우지 않는다. 그래서 `_hasChanges` 와 나눠 센다.
  bool _inviteChanged = false;

  /// 닫을 때 돌려줄 결과 — 다섯 군데가 같은 식을 쓴다.
  WorkApplicantsDialogResult get _dialogResult => WorkApplicantsDialogResult(
        hasChanges: _hasChanges || _inviteChanged,
        homeRelevant: _hasChanges,
        affectedTOIds: _affectedOtherTOIds,
      );
  // ✅ 로딩 상태
  bool _isProcessing = false;
  // 신분증 일괄 요청 모드
  bool _isIdCardSelectMode = false;
  final Set<String> _selectedIdCardUserIds = {};
  // 🔥 충돌로 취소된 다른 TO ID 목록
  final Set<String> _affectedOtherTOIds = {};
  // 이번 주 근무 횟수 (uid → 근무 횟수)
  final Map<String, int> _weeklyWorkCountMap = {};
  // 계약서 상태 (applicationId → status string, null=미작성)
  // [REISSUE-RECOVERY] 조회 실패(unresolved)와 "계약 없음"을 구별해 담는다.
  ContractStatusBatch _contractStatusMap = const ContractStatusBatch();

  /// [REISSUE-RECOVERY] **지금 이 지원서에 계약서를 보내는 것이 행동인가.**
  ///
  ///   두 사실의 곱이다.
  ///     · 계약서가 **없다고 확인됐다** — 조회 실패는 아니다(ERROR ≠ ZERO)
  ///     · 보낼 수 있는 관계다 — 좌석 반납(`staffingReleasedAt`)·해지 승인 제외
  ///       (서버 `srvNeedsContractIssue` 와 같은 한 벌: `isContractIssuable`)
  ///
  ///   미발송 탭·홈 할 일은 그 서버 판정을 쓴다. 여기가 다른 조건을 쓰면
  ///   같은 사실을 두 화면이 다르게 말한다.
  ///   [NOSHOW-CONTRACT-GUARD] 세 번째 사실 — 그 근무일 근태가 노쇼·결근이 아니다
  ///   (서버 `srvContractBlockedByAttendance` 와 같은 규칙, 근태를 모르면 단기는 아니다).
  bool _needsContractIssue(ApplicationModel app) =>
      _contractStatusMap.isMissingContract(app.id) &&
      app.isContractIssuable &&
      ContractAttendanceGate.clearForIssue(app, _contractBlockedAppIds);

  /// [NOSHOW-CONTRACT-GUARD] 노쇼·결근으로 기록된 지원서 id. null = 근태를 읽지 못했다.
  Set<String>? _contractBlockedAppIds;
  bool _contractAttRetrying = false;

  /// 근태 판정이 필요한 확정 단기 근무들 — 로드와 재시도가 같은 목록을 쓴다.
  static List<ApplicationModel> _contractAttCandidatesOf(
          Iterable<ApplicationModel> apps) =>
      apps
          .where((a) =>
              AppStatus.confirmedStatuses.contains(a.status) &&
              ContractAttendanceGate.attendanceDocId(a) != null)
          .toList();

  /// 근태를 몰라서 `계약서 작성` 을 **내지 않은** 행이 있는가 — 행 버튼과 같은 조건.
  bool get _contractAttendanceSuppressed =>
      _contractBlockedAppIds == null &&
      _canManageContract() &&
      _contractAttCandidatesOf(
              _applicants.map((i) => i['application'] as ApplicationModel))
          .any((a) =>
              _contractStatusMap.isMissingContract(a.id) &&
              a.isContractIssuable &&
              !_isEndedRelation(a));

  /// 근태만 다시 읽는다(명단 전체를 다시 부르지 않는다).
  Future<void> _retryContractAttendance() async {
    final read = _reads.contractAttendances;
    if (read == null || _contractAttRetrying) return;
    final candidates = _contractAttCandidatesOf(
        _applicants.map((i) => i['application'] as ApplicationModel));
    if (candidates.isEmpty) return;
    setState(() => _contractAttRetrying = true);
    final days = candidates.map((a) => a.workDate).toList()..sort();
    Set<String>? blocked;
    try {
      blocked = ContractAttendanceGate.blockedIds(
          candidates,
          await read(
              businessId: widget.toItem.to.businessId,
              first: days.first,
              last: days.last));
    } catch (e) {
      debugPrint('⚠️ [NOSHOW-CONTRACT-GUARD] 근태 재조회 실패: $e');
      blocked = null;
    }
    if (!mounted) return;
    setState(() {
      _contractBlockedAppIds = blocked;
      _contractAttRetrying = false;
    });
  }
  // 계약서 일괄작성 처리 중 플래그
  bool _isContractBatchProcessing = false;
  // [BUG-CANCEL-01] 확정취소 버튼 가드 — 근무 이력 있는 확정자 노출 방지
  // key = userId, value = 슬롯 날짜(or 주간)에 checkIn/급여확정 기록 존재 여부
  Map<String, bool> _hasWorkedMap = {};
  /// [R5.3E.2] 이 사업장의 진행 중인 근무 변경 제안.
  List<ConfirmedReassignmentProposal> _reassignProposals = const [];

  // [BIZCTX-PATCH] target business 기준 권한 판정.
  // [POSTING-V2-03B.1] 생성자 snapshot(targetPermissions)을 canonical로 쓰지 않는다.
  //   다이얼로그가 열려 있는 동안 권한이 회수돼도 처음 받은 값을 계속 써서
  //   확정·거절·초대 CTA가 남아 있었다. provider가 그 사업장 권한을 **LOADED**로
  //   갖고 있으면 그쪽이 canonical이고, 아직 UNKNOWN일 때만 snapshot으로 폴백한다.
  //   (UNKNOWN ≠ DENIED — 02G tri-state 유지)
  bool _permissionFor(bool Function(MemberPermissions p) check) {
    final up = context.read<UserProvider>();
    final user = up.currentUser;
    if (user == null) return false;
    if (user.isBusinessAdmin || user.isSuperAdmin) return true;
    if (!user.isSubAdmin) return false;
    if (up.subAdminPermissionsLoaded) {
      return up.canForBusiness(widget.toItem.to.businessId, check);
    }
    // 아직 하이드레이션 전 — 알림 경로가 정확히 조회해 넘긴 값을 쓴다.
    final target = widget.targetPermissions;
    if (target != null) return check(target);
    return false; // fail-closed
  }

  bool _canManageTo() => _permissionFor((p) => p.canManageTo);

  // ── [R7-P1-2.1] NO_PERMISSION != ERROR ────────────────────────────────
  //
  //   이 화면의 canonical capability 는 `canManageTo` 다 — 액션 게이트가 이미
  //   그것을 쓰고, 서버도 applicantReview 경로에서 같은 값을 strict 로 본다.
  //   `checkForBusiness` 는 **확인된 거부**와 **확인 실패**를 이미 구분한다.
  //   여기서 새 권한 상태 기계를 만들지 않고 그 판정을 그대로 쓴다.
  //
  //   unknown 일 때만 알림 경로가 넘긴 snapshot 으로 임시 판정한다 —
  //   `_permissionFor` 와 같은 순서다. snapshot 이 없으면 unknown 그대로 둔다.
  //   unknown 을 denied 로 추정하지 않는다(확인 실패로 남의 권한을 지우지 않는다).
  PermissionCheck _staffingPermission() {
    final up = context.read<UserProvider>();
    final r = up.checkForBusiness(
        widget.toItem.to.businessId, (p) => p.canManageTo);
    if (r != PermissionCheck.unknown) return r;
    final target = widget.targetPermissions;
    if (target != null) {
      return target.canManageTo
          ? PermissionCheck.allowed
          : PermissionCheck.denied;
    }
    return PermissionCheck.unknown;
  }

  /// 조회 실패가 **권한 거부**였는가 — code 로만 판정한다.
  ///
  ///   [R7-P1-2 DEVICE.1E.1] 판정식은 `applicant_load_outcome.dart` 하나다.
  ///   private State 안에 있으면 실행으로 증명할 수 없어서 떼어 냈다.
  static bool isPermissionDenial(Object error) =>
      isPermissionDenialError(error);

  // [CSA-02] canManageContract: canManageTo와 대칭 구조.
  bool _canManageContract() => _permissionFor((p) => p.canManageContract);

  // [CSA-01] Employer seal canonical resolver.
  // BUSINESS_ADMIN: 현재 사용자(사업주 본인) seal 사용.
  // SUB_ADMIN: business.ownerId 문서에서 사업주 seal 조회 — DayApplicants와 동일 semantics.
  // CF는 seal bytes 출처를 검증하지 않으므로 클라이언트가 올바른 owner seal을 사용해야 한다.
  // [CONTRACT-DISPATCH-B1] owner 날인은 **서버가** 찍는다. 앱은 owner 문서를 읽을 수 없다
  //   (사업장 목록은 ownerId 를 지우고 users 문서는 본인만 읽는다) — 그래서 예전 읽기는 늘 비어
  //   날인을 등록한 사업주도 '미등록' 이었다. 여기서는 있는지만 묻는다: true/false/null(모름).
  Future<bool?> _employerSealReady(BusinessModel business) =>
      BusinessPostingReadiness.employerSealReady(business.id);

  // [CSA-01] Seal 미등록 시 안내 메시지 — SubAdmin과 사업주 구분.
  Future<void> _showSealMissingDialog({required bool isBatchApprove}) async {
    final up = context.read<UserProvider>();
    final String message;
    final String confirmText;
    if (up.isSubAdmin) {
      message = isBatchApprove
          ? '일괄 계약 발송에는 사업주 날인이 필요합니다.\n사업주에게 날인 등록을 요청해주세요.'
          : '계약 발송에는 사업주 날인이 필요합니다.\n사업주에게 날인 등록을 요청해주세요.';
      confirmText = '확인';
    } else {
      message = isBatchApprove
          ? '일괄 계약 발송에는 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.'
          : '계약 발송에는 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.';
      confirmText = '설정으로 이동';
    }
    if (!mounted) return;
    final go = await DialogHelper.showConfirm(
      context,
      title: '사업주 날인 미등록',
      message: message,
      confirmText: confirmText,
      cancelText: '취소',
    );
    if (!mounted) return;
    if (go && !up.isSubAdmin) {
      Navigator.of(context, rootNavigator: true)
          .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    }
  }

  @override
  void initState() {
    super.initState();
    // [SYSTEM-INTEGRATION-R2.4 §16] 열자마자 실제 지원서로 인원 수치를 세운다.
    //
    //   알림에서 진입하면 이 다이얼로그는 `WorkDetailData.currentCount`로 만든
    //   TOItem을 받는다. 그 getter는 구 아키텍처 잔재라 **항상 0을 반환**한다.
    //   그래서 확정자가 3명인 업무를 알림으로 열면 `확정 0`이라고 적혀 있었고,
    //   확정 가능 인원 가드도 `required - 0`으로 계산돼 아무것도 막지 못했다.
    //   (서버 정원 가드는 그대로 동작하므로 초과 확정은 일어나지 않지만,
    //    화면이 현재 상태가 아닌 값을 말하고 있었다.)
    //
    //   지원서는 어차피 지금 불러온다 — 그 결과로 수치를 만든다.
    //   다른 표면과 같은 source이므로 숫자가 갈라지지 않는다.
    // [CROSS-DOMAIN-R5.1F.2] 이 다이얼로그의 사업장은 selected와 다를 수 있다
    //   (알림·deep-link 진입). 열려 있는 동안 그 사업장 권한만 구독한다.
    // [R7-P1-2 DEVICE.1E] 정원은 부모 snapshot 에 기대지 않고 직접 읽는다.
    //   첫 프레임은 부모가 준 값으로 그리고(깜빡임 방지), 곧바로 canonical
    //   조회로 덮는다. 사람 목록과 **독립**이다.
    _capacity.seed(widget.toItem.workDetailStats,
        parentFailed: widget.toItem.workDetailStatsFailed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _releasePermsWatch = context
          .read<UserProvider>()
          .watchBusinessPermissions(widget.toItem.to.businessId);
      _loadCapacity();
    });
    _loadApplicants().then((_) {
      if (mounted) _updateLocalStats(markChanged: false);
    });
    // [R5.3E.2] 진행 중인 변경 제안 — 확정 행의 CTA가 '변경 확인 대기'로
    //   바뀌려면 이 목록이 필요하다. 지원자 로드와 독립이므로 따로 시작한다.
    _loadReassignProposals();
  }

  VoidCallback? _releasePermsWatch;

  @override
  void dispose() {
    _releasePermsWatch?.call();
    // 진행 중인 정원 응답이 dispose 이후 상태를 건드리지 않게 한다.
    _capacity.dispose();
    super.dispose();
  }

  // ── [R7-P1-2] 로드 결과를 사실대로 말한다 ─────────────────────────────
  //
  //   여기서 쓰는 `runWithLoading`은 예외를 삼킨다. errorMessage 도 넘기지
  //   않았으므로 토스트조차 뜨지 않았다. 그래서 조회가 실패하면 `_applicants`
  //   가 빈 채로 남고 화면은 `지원자가 없습니다`라고 말했다 — 확정자가 있는
  //   업무에서도 그랬다. **읽지 못한 것과 없는 것은 다르다.**
  //
  //   그리고 실패에도 두 종류가 있다.
  //     최초 로드 실패   → 보여줄 것이 없다. ERROR 화면 + 다시 시도.
  //     새로고침 실패    → 이미 보여주던 명단은 여전히 쓸 만하다. 지우지 않는다.
  //   후자를 전자처럼 다루면, 확정 처리 직후 새로고침이 한 번 실패했다는
  //   이유로 방금까지 보던 명단이 통째로 사라진다.
  bool _loadOk = false;
  bool _hasLoadedOnce = false;
  bool _loadFailed = false;
  bool _refreshFailed = false;

  /// [R7-P1-2.1] 이번 조회가 **권한 거부**로 끝났는가.
  ///
  ///   일반 실패와 다른 축이다. 일반 실패는 기존 명단을 살려 두지만,
  ///   권한이 사라진 것이 확인되면 살려 두는 것 자체가 사고다 —
  ///   볼 자격을 잃은 사람이 이름·연락처를 계속 보게 된다.
  bool _loadDenied = false;

  /// 지원자 + 사용자 정보 + 신분증 상태 로드
  Future<void> _loadApplicants() async {
    _loadOk = false;
    _loadDenied = false;
    await _runLoadApplicants();
    if (!mounted) return;
    final ok = _loadOk;
    final denied = _loadDenied;
    final hadRows = _hasLoadedOnce;
    // [R7-P1-2 DEVICE.1E.1] 무엇으로 말할지는 `applicantLoadOutcome` 하나가 정한다.
    final outcome =
        applicantLoadOutcome(ok: ok, denied: denied, hadRows: hadRows);
    setState(() {
      _loadFailed = outcome.loadFailed;
      _refreshFailed = outcome.refreshFailed;
      if (ok) {
        _hasLoadedOnce = true;
      } else if (outcome.clearRows) {
        // [R7-P1-2.1] 확인된 권한 거부 — 낡은 명단을 남기지 않고 지운다.
        //   stale rows + 새로고침 배너 조합은 여기서 쓰지 않는다.
        // [R7-P1-2 DEVICE.1E.1] 읽어 둔 정원도 함께 지운다 — 권한을 잃은
        //   사람에게 자리 수치를 계속 보여 줄 이유가 없고, 진행 중이던
        //   정원 응답이 늦게 도착해 다시 노출되어서도 안 된다.
        _capacity.clearOnRevocation();
        _applicants = [];
        _allApplications = [];
        _invites = [];
        _groupApplicants();
        _idCardStatusMap = {};
        _contractStatusMap = const ContractStatusBatch();
        _hasWorkedMap = {};
        _weeklyWorkCountMap.clear();
        _starredIds.clear();
        _selectedIds.clear();
        _selectedIdCardUserIds.clear();
        _isBatchMode = false;
        _isIdCardSelectMode = false;
        _selectAll = false;
      }
      // refreshFailed → 기존 행은 그대로 둔다(PARTIAL 이지 EMPTY 가 아니다).
      // loadFailed    → 보여 줄 것이 없다(ERROR — `지원자 없음` 이 아니다).
    });
    if (denied) {
      ToastHelper.showWarning('지원자 정보를 볼 권한이 없습니다.');
      return;
    }
    if (!ok && hadRows) {
      ToastHelper.showError('최신 정보를 불러오지 못했습니다. 아래는 이전에 받은 내용입니다.');
    }
    // [E1-W3] 성공한 재조회에서만 미확인 초대를 판정한다.
    if (ok) _reconcileUnconfirmedInvites();
  }

  /// [E1-W3] 저장 여부를 확인하지 못한 채 닫힌 초대의 대상.
  ///
  ///   직접 초대 창이 `unconfirmed` 로 닫히고 저장 확인 읽기도 saved 를
  ///   주지 못하면(unknown·notSaved) 상위 전파를 하지 않는다 — 모름을 성공으로
  ///   추정하지 않는다. 그런데 이 창은 바로 이어서 자기 목록을 다시 읽고,
  ///   그 읽기가 성공해 **그 대상의 이 업무 INVITED 초대**를 보여 줄 수 있다.
  ///   예전에는 그래도 `hasChanges=false` 라 공고 카드가 다시 읽지 않았다
  ///   (창은 `초대 1`, 카드는 옛 `대기 0`).
  ///   여기 남겨 두었다가, 성공한 재조회에서 그 초대를 **읽었을 때만** 전파한다.
  final List<InviteVerifyTarget> _unconfirmedInviteTargets = [];

  /// [E1-W3] 방금 성공한 목록 읽기(`_invites` = 이 업무의 INVITED)에서
  ///   미확인 대상의 초대를 찾는다. 찾으면 전파하고 목록에서 뺀다.
  ///   조회 실패·다른 대상·다른 슬롯의 초대는 증거가 아니다.
  void _reconcileUnconfirmedInvites() {
    if (_unconfirmedInviteTargets.isEmpty) return;
    final found = <InviteVerifyTarget>[];
    for (final t in _unconfirmedInviteTargets) {
      final hit = _invites.any((item) {
        final a = item['application'] as ApplicationModel;
        return a.status == AppStatus.invited &&
            a.invitedAt != null &&
            a.uid == t.targetUid &&
            a.toId == t.toId &&
            (t.slotId == null || a.slotId == t.slotId);
      });
      if (hit) found.add(t);
    }
    if (found.isEmpty) return;
    _unconfirmedInviteTargets.removeWhere(found.contains);
    _inviteChanged = true;
    InviteSaveVerifier.announceClose(InviteSaveCheck.saved);
  }

  Future<void> _runLoadApplicants() => runWithLoading(() async {
      final userProvider = context.read<UserProvider>();
      final currentUserId = userProvider.currentUser?.uid ?? '';

      // 슬롯 기반 TO는 해당 슬롯 지원자만, 아니면 전체 TO 지원자 조회 (대기+확정만)
      // [BUGFIX] whereIn + equality 복합쿼리 시 Firestore 보안 규칙
      //   request.query.filters.businessId가 null 반환 → PERMISSION_DENIED.
      //   statuses 파라미터 제거 후 클라이언트 필터링으로 전환.
      // [R7-P1-2.1] 명단 조회가 canonical denial 신호다 — 여기서 code 를 잡는다.
      //   `runWithLoading` 이 바깥에서 예외를 삼키므로, 삼켜지기 전에 기록한다.
      final List<ApplicationModel> apps;
      try {
        // [R7-P1-2.2] purpose 를 반드시 넘긴다.
        //
        //   생략하면 서버는 membership-only 분기로 간다 — canManageTo 가 없는
        //   멤버에게도 지원서 payload 가 그대로 나간다. DEV 에서 실제로 그랬다
        //   (canManageTo=false 인데 count=50). UI 가 감추는 것은 authorization 이
        //   아니다. 이 화면의 UI 계약(canManageTo)과 서버 계약을 같게 만든다.
        apps = await _reads.applications(
          widget.toItem.to,
          slotId: widget.toItem.slot?.id,
          purpose: FirestoreService.purposeApplicantReview,
        );
      } catch (e) {
        _loadDenied = isPermissionDenial(e);
        rethrow;
      }

      // [E2-INVITED-SEAT] 업무 소속 판정을 지원·초대가 같이 쓰도록 떼어 냈다.
      //   상태 판정(PENDING/CONTRACT_PENDING/CONFIRMED · INVITED)은
      //   splitWorkApplications 가 한다.
      bool belongsToThisWork(ApplicationModel app) {
        if (widget.work != null) {
          // [R7-PRE0] canonical identity 로 먼저 맞춘다.
          //
          //   예전에는 app.workDetailId 를 work.id(= workType_start_end
          //   계산값)와 비교했다. 지원서의 workDetailId 는 문서형 ID 라
          //   둘이 같을 수 없었고, 확정자가 있는 근무를 열면
          //   `지원자가 없습니다`가 떴다 — 그 화면의 신분증 요청·계약서
          //   일괄작성 CTA 도 함께 사라졌다.
          final appWdId = app.wdId;
          final workWdId = widget.work!.wdId;
          if (appWdId != null && appWdId.isNotEmpty &&
              workWdId != null && workWdId.isNotEmpty) {
            return appWdId == workWdId;
          }

          // 아래는 wdId 가 없던 시절 데이터 — 기존 규칙 그대로 둔다.
          final wdId = app.workDetailId;
          if (wdId != null && wdId.isNotEmpty) {
            // 신규 compositeId 매칭
            if (wdId == widget.work!.id) return true;
            // 레거시: workDetailId = workType만 저장된 경우 → 시간으로 추가 확인
            if (wdId == widget.work!.workType) {
              return app.startTime == widget.work!.startTime &&
                     app.endTime == widget.work!.endTime;
            }
            return false;
          }
          // workDetailId 없는 구 데이터 호환
          return app.selectedWorkType == widget.work!.workType &&
                 app.startTime == widget.work!.startTime &&
                 app.endTime == widget.work!.endTime;
        }
        return true; // 그룹 모드: 업무 필터 없음 (상태 판정은 split 이 한다)
      }

      // [E2-INVITED-SEAT] 같은 응답을 지원·초대로 나눈다 — 초대는 지원 목록·일괄
      //   처리·계약 조회 대상에 넣지 않는다(초대는 관리자가 확정하지 않는다).
      final split = splitWorkApplications(apps, belongsToThisWork);
      final filtered = split.active;
      final invitedApps = split.invites;

      // ✅ 1. 중복 제거된 UID/ID 목록 추출
      //   초대받은 사람의 이름도 같은 batch 로 받는다(추가 왕복 없음).
      final uniqueUids = {
        ...filtered.map((app) => app.uid),
        ...invitedApps.map((app) => app.uid),
      }.toList();
      final allAppIds = filtered.map((app) => app.id).toList();

      // 날짜 범위 (weeklyMap Future 생성에 필요)
      final slotDate = widget.toItem.slot?.date;
      // [R7-P1-2 DEVICE.1G] 기준일은 **이 화면이 말하는 날짜**다.
      //
      //   여기는 `slotDate ?? DateTime.now()` 였다. 슬롯이 없는 진입에서는
      //   머리말이 2026-09-28 을 말하면서 주간 배지는 **오늘**이 속한 주를
      //   셌다. 같은 사람·같은 날짜를 두고 홈 일자별 화면과 다른 수가 나온
      //   경로다(DEV 실측: 주1회 vs 주0회).
      //
      //   `_headerScope` 가 쓰는 것과 같은 순서로 대상 날짜를 고른다.
      final refDate = slotDate ?? widget.initialDate ?? widget.toItem.to.date;
      final ws = WeekHelper.weekStart(refDate);
      final we = WeekHelper.weekEnd(refDate);

      // ✅ 2. 독립 조회 4개 동시 시작 (서로 의존성 없음)
      // hasWorkedMap은 슬롯 날짜 있을 때만 의미 있지만, 미리 시작해두면 크리티컬 패스에서 제외됨
      // [PII-DOC-R0.1 / INV-1] 지원자 목록 — 이름·나이·성별·연락처·평점·이력까지.
      //   이 화면은 계좌를 그리지 않는다. 그러니 받지도 않는다.
      final userMapFuture = _reads.usersBatch(
        uniqueUids,
        businessId: widget.toItem.to.businessId,
        purpose: FirestoreService.purposeWorkerDirectory,
      );
      final weeklyMapFuture = _reads.weeklyAttendance(
        businessId: widget.toItem.to.businessId, weekStart: ws, weekEnd: we);
      final contractMapFuture = _reads.contractStatusBatch(
        allAppIds, businessId: widget.toItem.to.businessId);
      final hasWorkedFuture = slotDate != null
          ? _reads.hasWorkedMap(
              businessId: widget.toItem.to.businessId, date: slotDate)
          : Future.value(<String, bool>{});

      // [NOSHOW-CONTRACT-GUARD] 확정 단기 근무들의 근무일 범위를 한 번에 읽는다.
      //   주간 근무횟수 조회(weeklyAttendance)는 실패를 빈 값으로 삼키고 범위도
      //   이번 주뿐이라 쓰지 않는다. 실패는 null(모름)로 남긴다.
      final contractCandidates = _contractAttCandidatesOf(filtered);
      final Future<Set<String>?> contractBlockedFuture;
      if (contractCandidates.isEmpty) {
        contractBlockedFuture = Future.value(<String>{});
      } else if (_reads.contractAttendances == null) {
        contractBlockedFuture = Future.value(null);
      } else {
        final days = contractCandidates.map((a) => a.workDate).toList()..sort();
        contractBlockedFuture = _reads.contractAttendances!(
          businessId: widget.toItem.to.businessId,
          first: days.first,
          last: days.last,
        ).then<Set<String>?>(
          (atts) => ContractAttendanceGate.blockedIds(contractCandidates, atts),
          onError: (Object e) {
            debugPrint('⚠️ [NOSHOW-CONTRACT-GUARD] 근태 조회 실패 — 계약 발행 판정 보류: $e');
            return null;
          },
        );
      }

      final userMap = await userMapFuture;
      
      // ✅ 3. 결과 매핑 (추가 조회 없음)
      final applicantsWithUserInfo = filtered.map((app) {
        return {
          'application': app,
          'user': userMap[app.uid],
        };
      }).toList();
      
      // 성명순 정렬
      applicantsWithUserInfo.sort((a, b) {
        final userA = a['user'] as UserModel?;
        final userB = b['user'] as UserModel?;
        if (userA == null || userB == null) return 0;
        return userA.name.compareTo(userB.name);
      });

      // 신분증 상태 일괄 조회 (확정자만)
      final confirmedUserIds = applicantsWithUserInfo
          .where((item) {
            final app = item['application'] as ApplicationModel;
            return item['user'] != null &&
                (app.status == AppStatus.confirmed || app.status == AppStatus.contractPending);
          })
          .map((item) => (item['user'] as UserModel).uid)
          .toList();
      
      final idCardStatusMap = await _reads.idCardStatusBatch(
        requesterId: currentUserId,
        targetUserIds: confirmedUserIds,
      );

      // [R7-P1-4 §11] 리뷰 작성 여부 조회 제거 — 이 화면은 리뷰를 말하지 않는다.
      //   확정자 1명당 문서 1개를 읽던 N-read 루프이기도 했다.

      // 이번 주 근무 횟수 — 위에서 동시에 시작한 weeklyMapFuture 결과 수집
      Map<String, List<dynamic>> weeklyMap;
      try {
        weeklyMap = await weeklyMapFuture;
      } catch (e) {
        debugPrint('⚠️ 주간 근무 횟수 조회 실패 (배지 미표시): $e');
        weeklyMap = {};
      }
      // 모든 지원자 uid를 0으로 초기화 → 기록 없는 지원자도 "주0회" 배지 표시
      final weeklyCountMap = <String, int>{
        for (final uid in uniqueUids) uid: 0,
      };
      // [R7-P1-2 DEVICE.1G] 세는 규칙은 `WeekHelper.workedDayCount` 하나다.
      //
      //   여기는 `.length` 로 **문서 수**를 셌다. DEV 실측에서 한 사람의
      //   9/20 에 출근 문서가 4건 있어 하루가 `주4회` 가 될 수 있었다.
      //   바로 위 주석이 처음부터 "근무한 날 기준"이라고 적고 있었다.
      for (final entry in weeklyMap.entries) {
        weeklyCountMap[entry.key] =
            WeekHelper.workedDayCount(entry.value.whereType<AttendanceModel>());
      }

      // isStarred 필드에서 관심표시 복원
      final starredFromFirestore = filtered
          .where((app) => app.isStarred)
          .map((app) => app.id)
          .toSet();

      // 계약서 상태 — 위에서 동시에 시작한 contractMapFuture 결과 수집
      final contractMap = await contractMapFuture;
      final contractBlocked = await contractBlockedFuture;

      // [BUG-CANCEL-01] 확정취소 버튼 가드 — 근무 이력 맵 구성
      // 슬롯 기반: hasWorkedFuture (위에서 동시 시작) 결과 수집
      // 비슬롯: 이미 로드된 weeklyMap 에서 app.workDate 매칭으로 근무 여부 파악
      final Map<String, bool> hasWorkedMap;
      if (slotDate != null && confirmedUserIds.isNotEmpty) {
        hasWorkedMap = await hasWorkedFuture;
      } else {
        hasWorkedMap = {};
        final confirmedShortTermApps = filtered.where((app) =>
            (app.status == AppStatus.confirmed ||
                app.status == AppStatus.contractPending) &&
            !app.isLongTermApplication);
        for (final app in confirmedShortTermApps) {
          final appDay = DateTime(
              app.workDate.year, app.workDate.month, app.workDate.day);
          final userAtts = (weeklyMap[app.uid] ?? []).whereType<AttendanceModel>().toList();
          for (final att in userAtts) {
            final attDay = DateTime(
                att.workDate.year, att.workDate.month, att.workDate.day);
            if (attDay == appDay) {
              if ((att.checkIn != null &&
                      att.status != AttendanceModel.statusAbsent &&
                      att.status != AttendanceModel.statusNoShow) ||
                  att.isWageConfirmed ||
                  att.isWageTransferred) {
                hasWorkedMap[app.uid] = true;
              }
              break;
            }
          }
        }
      }

      // 알림 딥링크로 진입 시 해당 지원자를 목록 맨 앞으로 이동
      if (widget.initialApplicationId != null) {
        final idx = applicantsWithUserInfo.indexWhere(
          (item) => (item['application'] as ApplicationModel).id == widget.initialApplicationId,
        );
        if (idx > 0) {
          final highlighted = applicantsWithUserInfo.removeAt(idx);
          applicantsWithUserInfo.insert(0, highlighted);
        }
      }

      // 여기까지 왔으면 조회는 끝났다 — unmount 여부와 무관하게 성공이다.
      _loadOk = true;
      if (!mounted) return;
      setState(() {
        _applicants = applicantsWithUserInfo;
        _invites = [
          for (final app in invitedApps)
            {'application': app, 'user': userMap[app.uid]},
        ];
        _groupApplicants();
        _idCardStatusMap = idCardStatusMap;
        _allApplications = apps; // 통계 계산용 캐시
        _starredIds
          ..clear()
          ..addAll(starredFromFirestore);
        _weeklyWorkCountMap
          ..clear()
          ..addAll(weeklyCountMap);
        _contractStatusMap = contractMap;
        _contractBlockedAppIds = contractBlocked; // [NOSHOW-CONTRACT-GUARD]
        _contractAttRetrying = false;
        _hasWorkedMap = hasWorkedMap; // [BUG-CANCEL-01]
      });
  }, errorTag: '지원자 목록 로드');

  void _groupApplicants() {
    _pending = _applicants.where((item) =>
        (item['application'] as ApplicationModel).status == AppStatus.pending).toList();
    final all = _applicants.where((item) {
      final s = (item['application'] as ApplicationModel).status;
      return AppStatus.confirmedStatuses.contains(s);
    }).toList();
    // [R7-P1-2 DEVICE.1E] 확정 이력과 **현재 근무 관계**를 나눈다.
    //
    //   status 만 보면 9/22 에 끝난 장기 약속이 9/27 에도 `확정 1명` 으로
    //   서 있고, `계약서 작성 필요` 배지와 `계약서 작성` 버튼까지 달고
    //   나온다 — 끝난 관계에 새 근로계약을 맺으라는 **없는 할 일**이다.
    //
    // [R7-P1-2 DEVICE.1E.1] 그런데 `occupiesSeatOn` 하나로 가른 것이 틀렸다.
    //
    //   그것은 **좌석** 판정이지 **관계 종료** 판정이 아니다. 만료됐지만
    //   연장/종료를 아직 결정하지 않은 사람까지 `계약 종료` 로 적어
    //   관리자의 할 일을 지웠고, 좌석을 반납한(대체충원) 사람은 반대로
    //   현재 인력으로 세어 정원 집계와 갈렸다.
    //
    //   판정은 `staffingRelationOf` 한 곳이 한다 — 기존 canonical 사실
    //   셋을 조합할 뿐, 새 정책을 만들지 않는다.
    //
    //   어느 경우에도 사람을 목록에서 지우지 않는다. 자리를 옮길 뿐이다.
    final now = _workApplicantsNow();
    _confirmed = <Map<String, dynamic>>[];
    _released = <Map<String, dynamic>>[];
    _decisionPending = <Map<String, dynamic>>[];
    _ended = <Map<String, dynamic>>[];
    for (final item in all) {
      final r = staffingRelationOf(item['application'] as ApplicationModel, now);
      if (r.decisionPending) {
        _decisionPending.add(item);
      } else if (r.resolvedEnded) {
        _ended.add(item);
      } else if (r.seatReleased) {
        _released.add(item);
      } else {
        _confirmed.add(item);
      }
    }
  }

  /// 이 행이 **결정까지 끝난 이력**인가.
  ///
  ///   만료+미결정(`decisionPending`)은 여기 들어오지 않는다 — 그 사람에게는
  ///   아직 할 일이 남아 있고, 액션을 내리면 그 일이 사라진다.
  bool _isEndedRelation(ApplicationModel app) =>
      staffingRelationOf(app, _workApplicantsNow()).resolvedEnded;

  /// 전체 선택/해제
  void _toggleSelectAll(bool? value) {
    final pendingApps = _applicants
        .where((item) => (item['application'] as ApplicationModel).status == AppStatus.pending)
        .map((item) => (item['application'] as ApplicationModel).id)
        .toList();

    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedIds.addAll(pendingApps);
      } else {
        _selectedIds.clear();
      }
    });
  }

  /// 개별 선택
  void _toggleSelection(String appId) {
    setState(() {
      if (_selectedIds.contains(appId)) {
        _selectedIds.remove(appId);
      } else {
        _selectedIds.add(appId);
      }
      
      final pendingCount = _applicants
          .where((item) => (item['application'] as ApplicationModel).status == AppStatus.pending)
          .length;
      _selectAll = _selectedIds.length == pendingCount && pendingCount > 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [POSTING-V2-03B.1] 대상 사업장 권한이 바뀌면 이 다이얼로그도 다시 그린다.
    //   _permissionFor는 read로 평가되므로(이벤트 핸들러에서도 호출된다)
    //   구독은 여기 한 줄로만 건다.
    context.watch<UserProvider>();

    final pending = _pending;
    final confirmed = _confirmed;

    // [R7-P1-2.1] 권한이 사라진 것이 **확인되면** 이 화면은 아무것도 말하지 않는다.
    //
    //   두 경로가 같은 결론으로 모인다.
    //     · 구독이 회수를 밀어 준 경우 → checkForBusiness == denied
    //     · 새로고침이 거부로 끝난 경우 → _loadDenied (error code)
    //   어느 쪽이든 이름·연락처·행 액션·일괄 액션·초대 진입이 전부 사라진다.
    //   unknown / error 는 여기 오지 않는다 — 확인 실패로 권한을 지우지 않는다.
    final noPermission =
        _staffingPermission() == PermissionCheck.denied || _loadDenied;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.pop(context, _dialogResult);
        }
      },
      child: AppModalShell(
        children: [
          // [DU532] 머리 모양과 본문 배치를 한 값(narrow)으로 함께 고른다 — _headAndBody 가 '전체형 머리 아래 남는 칸'을 먼저 잰다.
          // [DU528] 통계 · 초대 · 전체 선택 줄과 본문을 한 칸으로 묶어 그 칸의 실제 높이를 잰다(_measuredBody = 남은 칸 + LayoutBuilder).
          ..._headAndBody(context, theme, widget.work != null && !noPermission, (context, box, narrow) {
          final strips = <Widget>[
          if (!noPermission) ...[
          if (narrow) _buildHeadInfoRow(context),
          _buildStatsBar(context, pending.length, confirmed.length, compact: narrow),
          // [R7-P1-3] 부족 해소 진입 — Day와 같은 자리, 같은 조건.
          if (!isLoading) _buildStaffingActionRow(context),
          // [R7-P1-PRODUCT §17] 게이트가 `pending.isNotEmpty`였다 — 1명이어도
          //   일괄선택이 떴다. 이 행의 bulk 대상은 PENDING 지원자(확정·거절
          //   일괄)이고, 1명은 개인 카드의 action이 이미 처리한다. 같은 일이
          //   두 군데서 강하게 보이는 것이 R7-P1-5에서 정한 계약 위반이다.
          //
          //   이미 bulk mode에 들어가 있는데 대상이 1명으로 줄면 계속 보여
          //   준다 — 그러지 않으면 `취소` 버튼까지 사라져 빠져나갈 수 없다.
          if (widget.work != null && (pending.length >= 2 || _isBatchMode))
            _buildSelectAllRow(context, pending.length),
          // [R7-P1-2] 새로고침만 실패했다 — 명단은 그대로 두고 그 사실만 알린다.
          if (!isLoading && _refreshFailed && !_loadFailed)
            _buildRefreshFailedBanner(context),
          ],
          ];
          // [DU528] 좁은 창 — 이 칸(창 최대 높이 − 머리 − 하단)이 화면 높이의 60% 에 못 미치면 통계 · 초대 · 전체 선택 줄을
          //   목록과 같은 스크롤 안 첫 항목으로 보낸다. 320×640 · 글자 2.0 에서 이 칸은 약 304(47%)인데 세 줄이 약 372 라
          //   목록 칸 높이가 0 이었다(DU527a r3 B: 창 Column 아래 넘침 69). 390×844 · 1.0 은 약 77% — 이전 배치 그대로.
          //   글자 배율 상수는 쓰지 않는다(실측 높이만). 업무별 창(work != null)만 — 묶음 창 · 권한 없음은 이전과 같다.
          // [DU532] narrow 면 머리가 짧아져 이 칸이 60% 를 넘을 수 있다 — 그래도 세 줄은 스크롤 안에 둔다(narrow 는 머리 모양과 무관한 값이라 뒤집히지 않는다).
          final tight = narrow ||
              (widget.work != null &&
              !noPermission &&
              box.maxHeight < MediaQuery.sizeOf(context).height * 0.6);
          final lead = tight ? strips : const <Widget>[];
          // [R7-P1-2 DEVICE.1G] `Expanded` → `Flexible`.
          //
          //   `AppModalShell` 은 `Column(mainAxisSize: min)` 이라 내용만큼
          //   줄어들도록 설계돼 있고, 그 문서도 `Flexible(child: body)` 를
          //   규정한다. `Expanded` 는 남은 공간을 **강제로 채우므로**
          //   높이가 항상 화면의 95% 가 됐다 — 확정 1명인 화면에서 아래쪽
          //   절반이 빈 채로 남았다.
          //
          //   고정 높이를 없애거나 전체화면으로 바꾸는 것이 아니다.
          //   본문이 스크롤 가능한 것은 그대로다(내부 SingleChildScrollView).
          //   많은 행에서는 여전히 maxHeight 까지 자라고 그 안에서 스크롤한다.
          final Widget body = noPermission
                // [R7-P1-2.1] 권한 없음 — 실패도 아니고 0명도 아니다.
                ? _buildNoPermissionState()
                : isLoading
                    ? const LoadingWidget()
                    // [R7-P1-2] ERROR != ZERO — 읽지 못한 것을 `없다`로 말하지 않는다.
                    : _loadFailed
                        ? _buildLoadErrorState()
                        // [E2-INVITED-SEAT] 초대만 있는 업무는 빈 화면이 아니다.
                        : (pending.isEmpty &&
                                confirmed.isEmpty &&
                                _invites.isEmpty &&
                                _ended.isEmpty &&
                                _decisionPending.isEmpty &&
                                _released.isEmpty)
                            ? _buildEmptyState()
                            : widget.work == null
                                ? _buildGroupedApplicantList(context)
                                : _buildApplicantList(
                                    context, pending, confirmed, leading: lead);
          // 좁은 창 + 명단: 세 줄은 이미 명단 스크롤 안에 있다(_buildApplicantList 의 leading).
          if (tight && body is SingleChildScrollView) return body;
          // 좁은 창 + 불러오는 중 · 실패 · 빈 상태: 세 줄과 본문을 한 스크롤에 둔다(넘침 대신 스크롤).
          // [DU530] 빈 상태 · 조회 실패 본문(AppEmptyState)은 받은 최대 높이를 최소 높이로 쓴다 — 스크롤 안(높이 제한 없음)에
          //   그대로 두면 무한 높이를 강제한다(감사129 F129-EMPTY-UNBOUNDED). 이 칸의 실측 최대 높이(box.maxHeight · 유한)를 준다.
          //   불러오는 중은 내용만큼(이전과 같다 — 통계 줄 바로 아래).
          if (tight) {
            return SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              ...strips,
              if (isLoading) body else SizedBox(height: box.maxHeight, child: body),
            ]));
          }
          // 그 밖(이전 배치 그대로): 세 줄 고정 + 본문.
          return Column(
              mainAxisSize: MainAxisSize.min,
              children: [...strips, Flexible(child: body)]);
          }),
          // 권한이 없으면 일괄 확정·거절이 있는 하단 바를 세우지 않는다.
          if (noPermission) _buildCloseOnlyBar(context) else _buildBottomBar(context),
        ],
      ),
    );
  }

  /// [R7-P1-2 DEVICE.1E §8] 이 화면이 다루는 **범위**.
  ///
  ///   장기 공고인데 머리말이 `9/9 (수)` 한 날짜만 말했다. 9/9~10/23 을
  ///   운영하는 공고에서 그 한 줄은 "9월 9일 하루의 인력 현황"으로 읽힌다.
  ///   단기는 실제로 하루짜리 모집 단위이므로 그대로 둔다 — 장기만 기간을
  ///   말한다.
  ///
  ///   공고의 기간이다. 이 사람의 계약 기간이 아니다(그건 행이 말한다).
  String get _headerScope {
    final to = widget.toItem.to;
    if (to.isLongTerm && widget.toItem.slot == null) {
      final start = to.rangeStart;
      final end = to.rangeEnd;
      if (start != null && end != null) {
        return '장기 ${FormatHelper.formatDateShort(start)}~'
            '${FormatHelper.formatDateShort(end)}';
      }
      // 기간을 모르면 지어내지 않는다.
      if (start != null) return '장기 ${FormatHelper.formatDateShort(start)}~';
      return '장기';
    }
    return FormatHelper.formatDate(
        widget.toItem.slot?.date ?? widget.initialDate ?? to.date);
  }

  /// 머리 제목 원문. [R7-P1-7 §15] `지원자 관리` → `인력 현황` — Day와 같은 이름.
  String get _headerTitle => widget.work != null
      ? '${widget.work!.workType} · 인력 현황'
      : '${widget.toItem.to.title} · 인력 현황';

  /// 머리 보조 줄(날짜/범위 · 시간 · 임금) — 머리 안과 좁은 창의 본문 첫 항목이 같은 위젯을 쓴다(글 · 읽는 이름 한 곳).
  Widget _headerSub() => Text.rich(
        TextSpan(
          text: widget.work != null
              ? '${TextLayout.phrases('$_headerScope · ${widget.work!.startTime}~${widget.work!.endTime}')} '
                '${TextLayout.unit('| ${widget.work!.wageTypeLabel}')} ${TextLayout.unit(widget.work!.formattedWage)}'
              : TextLayout.phrases('$_headerScope · 업무 ${widget.toItem.workDetails.length}종'),
          semanticsLabel: widget.work != null
            ? '$_headerScope · ${widget.work!.startTime}~${widget.work!.endTime}'
              ' | ${widget.work!.wageTypeLabel} ${widget.work!.formattedWage}'
            : '$_headerScope · 업무 ${widget.toItem.workDetails.length}종',
        ),
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: AppColors.textSecondary,
        ),
      );

  /// [DU532] 좁은 업무별 창에서 머리 대신 본문 스크롤의 첫 항목으로 서는 보조 줄(통계 줄과 같은 여백 · 흰 바탕).
  Widget _buildHeadInfoRow(BuildContext context) => Container(
        width: double.infinity,
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16), vertical: ResponsiveHelper.spacing(context, 12)),
        child: _headerSub(),
      );

  /// 헤더 — ALfit modal grammar (flat white + grey200 divider)
  ///   [DU532] [dense] 면 제목 · 닫기만 둔다(보조 줄은 본문 첫 항목 — _buildHeadInfoRow).
  Widget _buildHeader(BuildContext context, ThemeData theme, {bool dense = false}) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppDialogSize.borderRadius),
          topRight: Radius.circular(AppDialogSize.borderRadius),
        ),
        border: Border(bottom: BorderSide(color: AppColors.grey200)),
      ),
      child: Row(
        children: [
          // 업무 아이콘 (그룹 모드: grey 플레이스홀더, 단일 모드: 업무 아이콘)
          if (widget.work != null)
            WorkTypeIcon.buildWithBackground(
              iconString: widget.work!.workTypeIcon,
              backgroundColor: widget.work!.workTypeBackgroundColor,
              size: ResponsiveHelper.iconSize(context, 24),
              containerSize: ResponsiveHelper.spacing(context, 44),
            )
          else
            Container(
              width: ResponsiveHelper.spacing(context, 44),
              height: ResponsiveHelper.spacing(context, 44),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
              ),
              child: Icon(Icons.people, color: AppColors.grey500, size: ResponsiveHelper.iconSize(context, 24)),
            ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),

          // 제목
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // [DU530] 큰 글자(320×640 · 2.0)에서 제목이 '홀서빙 · …'로 잘리고 보조 줄은 금액 끝 '원' 한 글자만 다음 줄로 떨어졌다.
                //   말줄임을 빼고 줄은 공백에서만 바꾼다(구분점 · 세로줄은 옆 낱말에 붙인다). 글 원문 · 읽는 이름은 그대로(span 의 semanticsLabel).
                Text.rich(
                  TextSpan(
                    text: TextLayout.phrases(_headerTitle),
                    semanticsLabel: _headerTitle,
                  ),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (!dense) _headerSub(),
              ],
            ),
          ),

          // 닫기 버튼
          IconButton(
            onPressed: () => Navigator.pop(context, _dialogResult),
            icon: const Icon(Icons.close, color: AppColors.grey500, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }

  // ── [R7-P1-3] staffing parity ──────────────────────────────────────────
  //
  // DayApplicantsDialog와 이 화면은 **같은 모집 단위**를 여는 두 개의 문이다.
  // 그런데 이쪽은 `지원 N · 확정 N · 필요 N명`까지만 말하고 부족도 초대도
  // 없었다. 같은 자리가 어느 문으로 들어오느냐에 따라 `2명 부족 + 인력 초대`
  // 이기도 하고 아무 말도 없기도 했다 — business truth가 진입경로를 탄 것이다.
  //
  // 공식을 여기서 새로 쓰지 않는다. `inviteCapacityStateOf`와
  // `staffingShortageOf` — DayApplicantsDialog가 쓰는 바로 그 두 함수다.

  // ── [R7-P1-2 DEVICE.1E] 정원은 이 화면이 **직접** 읽는다 ────────────────
  //
  //   여기는 `widget.toItem.workDetailStats` 하나만 봤다. 그 map 은 부모
  //   카드가 만들어 넘긴 **생성 시점의 snapshot** 이다. 다이얼로그는 그것을
  //   갱신할 수단이 없었다 — `정원 확인 불가` 옆의 `다시 시도` 는
  //   `_loadApplicants` 를 불렀고, 그 함수는 지원서만 다시 읽는다.
  //
  //   그래서 카드가 통계를 아직 못 받은 순간에 행을 누르면, 다이얼로그는
  //   그 빈 snapshot 을 붙든 채 열리고 **닫을 때까지 영원히** `정원 확인
  //   불가` 였다. 뒤에서 카드가 채워져도 따라오지 못한다. DEV 에서 확인한
  //   대로 서버 정원 조회 자체는 성공한다 — 읽을 기회가 없었을 뿐이다.
  //
  //   새 API·새 purpose 를 만들지 않는다. 카드가 쓰는 `loadTOWorkDetails`
  //   그대로다(내부는 이미 `purposeCapacity` 축소 projection).
  //
  //   사람 목록과 **독립된** 로드 상태를 갖는다 — 한쪽 실패가 다른 쪽을
  //   지우지 않는다(§5).
  //   [R7-P1-2 DEVICE.1E.1] 그 상태기계를 화면에서 분리했다 —
  //   실패→재시도·순서 역전·dispose·권한 회수를 실행으로 증명하기 위해서다.
  //   화면은 그 객체를 그대로 쓴다(테스트 전용 분기 없음).
  late final CapacityLoadState _capacity = CapacityLoadState(
    loader: () => _reads.capacity(
      widget.toItem.to,
      slotId: widget.toItem.slot?.id,
      slotWorkDetails: widget.toItem.slot?.workDetails,
    ),
    onChanged: () {
      if (mounted) setState(() {});
    },
  );

  bool get _capacityLoading => _capacity.loading;

  Future<void> _loadCapacity() async {
    if (widget.work == null) return; // 그룹 모드 — 단일 capacity 없음
    await _capacity.load();
  }

  /// [R7-4 C5·C6] 승인 전 정원 관문 — 단건 승인과 일괄 승인이 **같은 계약**을 쓴다.
  ///
  ///   막을 이유가 있으면 그 문구를, 없으면 null 을 돌려준다.
  ///
  ///   예전에는 두 자리가 각각 `stats?['confirmed'] ?? 0` 으로 정원을 읽었다.
  ///   identity 가 빗나가면 확정 수가 0 이 되고, 남은 자리는 정원만큼 열려
  ///   있는 것처럼 보였다. 정원이 다 찬 업무에서 승인 버튼이 열리고,
  ///   `현재 0명 확정`이라는 틀린 문장까지 붙었다.
  ///
  ///   모르는 것은 0 이 아니다. 모르면 모른다고 말하고 멈춘다 —
  ///   대기(UNKNOWN)를 `인원 충족`이라고 바꿔 말하지도 않는다.
  ///
  ///   이 판정은 **최종 권위가 아니다.** 마지막 한 자리를 두고 동시에 누르는
  ///   경우는 서버 transaction 이 막는다. 여기서 하는 일은 서버가 거절할 것을
  ///   미리 알려 주는 것뿐이다.
  ///   판정 본체는 [capacityBlockReason] 에 있다 — 화면 없이 실행해 확인한다.
  ///   여기서는 canonical 확정 수를 어디서 읽는지만 정한다.
  String? _capacityBlockReason(WorkDetailModel? work, int addCount) {
    if (work == null) return null;
    return capacityBlockReason(
      confirmed: _capacity.confirmedFor(work),
      requiredCount: work.requiredCount,
      addCount: addCount,
    );
  }

  /// 이 업무의 canonical 확정 수. 정원 조회가 말하는 값이고, 못 읽었으면 null.
  ///
  /// 지원서에서 세지 않는다 — 이 다이얼로그가 로드한 지원서는 권한·페이징에
  /// 따라 일부일 수 있고, 그 부분집합으로 정원을 판정하면 `부족`이 부풀려진다.
  int? get _canonicalConfirmed => _capacity.confirmedFor(widget.work);

  /// 이 모집 단위가 지금 초대를 받을 수 있는가 — Day와 같은 세 상태 + UNKNOWN.
  InviteCapacityState get _capacityState => inviteCapacityStateOf(
        canonicalConfirmed: _canonicalConfirmed,
        requiredCount: widget.work?.requiredCount ?? 0,
        isClosed: CloseStateUtils.isToItemClosed(
            widget.toItem, widget.toItem.to, _workApplicantsNow()),
      );

  /// 부족 — null이면 확인하지 못했다는 뜻이다 (UNKNOWN != ZERO).
  int? get _shortage {
    final work = widget.work;
    if (work == null) return null;
    // 좌석을 반납한 확정(NO_SHOW 대체충원)은 정원을 소모하지 않는다.
    final seated = _applicants.where((item) {
      final a = item['application'] as ApplicationModel;
      return _appMatchesWork(a, work) &&
          AppStatus.confirmedStatuses.contains(a.status) &&
          !a.isStaffingReleased;
    }).length;
    final canonical = _canonicalConfirmed;
    return staffingShortageOf(
      capacity: _capacityState,
      requiredCount: work.requiredCount,
      // canonical을 우선한다 — 화면 목록은 부분집합일 수 있다.
      seatedConfirmed: canonical ?? seated,
    );
  }

  /// 통계 바
  ///   [DU533] [compact](좁은 업무별 창 = DU532 의 narrow)이면 항목을 내용 폭으로 줄여 아래 Wrap 이 가로로 흘린다(항목 단위 줄바꿈).
  ///   항목 · 글 · 색 · 순서 · 표시 조건은 그대로다. 넓은 창 · 묶음 창은 이전처럼 항목마다 한 줄.
  Widget _buildStatsBar(BuildContext context, int pendingCount, int confirmedCount, {bool compact = false}) {
    final work = widget.work;
    final shortage = _shortage;
    final capacity = _capacityState;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      // [R7-P1-PRODUCT] Row → Wrap.
      //
      //   Row에 `지원 · 확정 · Spacer · 필요` 셋이 있던 자리에 `부족`을
      //   더하면서 360dp에서 넘칠 수 있는 구조가 됐다. 이 Row에는
      //   Flexible이 하나도 없어 Text가 줄지 못하고, Spacer는 0 아래로
      //   내려가지 못한다 — 폰트 배율을 키우거나 `정원 확인 불가`가 뜨면
      //   RenderFlex overflow다.
      //
      //   Wrap이면 좁을 때 둘째 줄로 흐르고 아무것도 잘리지 않는다.
      //   (CLAUDE.md: 텍스트+아이콘 조합이 길어지면 Wrap으로 줄바꿈 허용)
      //   우측 정렬 하나를 포기하는 대신 네 사실이 모두 남는다.
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: ResponsiveHelper.spacing(context, 14),
        runSpacing: ResponsiveHelper.spacing(context, 6),
        children: [
          // [R7-P1-2 DEVICE.1G] 0 은 처리할 일이 아니다.
          //
          //   orange 는 이 앱의 색 계약에서 **지금 처리 가능한 미완료**다.
          //   `지원 0` 에 그것을 쓰면 없는 할 일을 강조하고, 바로 옆
          //   `부족 2` 와 같은 경고 강도로 경쟁한다. 같은 파일의 `부족` 이
          //   이미 `> 0` 일 때만 강조하고 있었다 — 같은 규칙을 맞춘다.
          // [UI-APPLICANTS-AND-INVITATIONS.2] 지원·초대·확정 수는 사실이다 — 의미색은 부족(처리할 일)에만.
          _buildStatItem(context, '지원', pendingCount,
              pendingCount > 0 ? AppColors.textPrimary : AppColors.grey500, compact: compact),
          // [E2-INVITED-SEAT] 직접 지원과 초대를 나눠 말한다 — `지원 0 · 초대 1`.
          //   0 이면 세우지 않는다(초대가 없는 업무에 빈 칸을 늘리지 않는다).
          if (_invites.isNotEmpty)
            _buildStatItem(context, '초대', _invites.length, AppColors.textPrimary, compact: compact),
          _buildStatItem(context, '확정', confirmedCount,
              confirmedCount > 0 ? AppColors.textPrimary : AppColors.grey500, compact: compact),
          // [R7-P1-6] 부족은 실패가 아니라 **지금 처리 가능한 미완료**다.
          //   red는 NO_SHOW·실패에 남겨 둔다.
          if (work != null && shortage != null)
            _buildStatItem(context, '부족', shortage,
                shortage > 0 ? AppColors.warningDark : AppColors.grey500, compact: compact),
          // [R7-P1-2 DEVICE.1E.2A] 정원 문구는 전용 component 가 그린다.
          //
          //   필요 인원은 공고가 정한 값이라 조회 상태와 무관하게 유효하다 —
          //   `정원 확인 불가`로 통째로 대체하면 알 수 있는 것까지 잃는다.
          //   충원 수는 canonical 일 때만 적는다(그 규칙은 위젯이 갖는다).
          if (work != null)
            CapacitySummaryText(
              requiredCount: work.requiredCount,
              capacity: capacity,
              isPending: _capacity.isPending,
            ),
        ],
      ),
    );
  }

  /// [R7-P1-3] 부족 해소 진입 — Day와 같은 조건, 같은 시트.
  ///
  /// `FULL`·`CLOSED`·`UNKNOWN`에서는 서지 않는다. 특히 UNKNOWN에서 CTA를 띄우면
  /// 확인하지 못한 부족을 확인한 것처럼 말하게 되고, 보내도 수락될 수 없는
  /// 초대를 낳는다. 대신 그 자리에 왜 판단할 수 없는지를 남긴다.
  Widget _buildStaffingActionRow(BuildContext context) {
    final work = widget.work;
    if (work == null) return const SizedBox.shrink();
    if (!_canManageTo()) return const SizedBox.shrink();

    final capacity = _capacityState;
    // [R7-P1R] UNKNOWN 안내는 subtype과 무관하다.
    //
    //   여기에 `if (isLongTerm) return SizedBox.shrink()`가 있었다. 초대
    //   CTA를 막으려던 것인데, 그 한 줄이 **왜 판단할 수 없는지**를 말하는
    //   안내와 `다시 시도`까지 함께 지웠다. 장기 공고에서는 통계가 아직
    //   로드되지 않았을 때 `정원 확인 불가`만 보이고 복구 수단이 없었다.
    //   ERROR != ZERO를 지키려고 만든 표면이 subtype 때문에 사라진 것이다.
    if (capacity == InviteCapacityState.unknown) {
      // [R7-P1-2 DEVICE.1E.2] 갱신 중에는 오류 안내를 세우지 않는다.
      //
      //   mutation 은 성공했다. 여기서 `확인하지 못했어요 + 다시 시도`를
      //   띄우면 관리자는 방금 한 확정·취소가 실패한 줄 알고 다시 누른다 —
      //   중복 약속을 만드는 안내다. 조회가 끝나면 정상 수치로 대체된다.
      if (_capacity.isPending) return _buildCapacityPendingNotice(context);
      return _buildCapacityUnknownNotice(context);
    }
    // 초대 CTA만 단기로 제한한다 — 이 화면에는 장기 약속 범위가 없다.
    //   장기 초대는 당일 명단(약속 범위를 canonical row로 받는다)과
    //   공고 ⋮ 메뉴가 맡는다.
    //
    // [R7-P1-2 DEVICE.1E.1 §6] 다만 **아무 말도 하지 않는 것**은 다른 문제다.
    //
    //   화면은 `부족 2`를 보여 주면서 다음 경로를 말하지 않았다. 관리자는
    //   부족을 보고 여기서 할 수 있는 일이 없다는 것만 알게 된다.
    //   초대를 여기서 열지 않는 이유는 권한이 아니라 **약속 범위가 없기
    //   때문**이고, 실제 경로는 공고 카드의 ⋮ 메뉴다(거기 게이트는
    //   `_canInviteNow` — 마감·충원 상태를 따로 본다).
    //
    //   새 초대 경로를 만들지 않는다. 있는 길을 가리킬 뿐이다.
    if (widget.toItem.to.isLongTerm) {
      final shortage = _shortage ?? 0;
      if (capacity == InviteCapacityState.available && shortage > 0) {
        return _buildLongTermShortageRoute(context, shortage);
      }
      return const SizedBox.shrink();
    }
    if (capacity != InviteCapacityState.available) {
      return const SizedBox.shrink();
    }
    final shortage = _shortage ?? 0;
    if (shortage <= 0) return const SizedBox.shrink();
    final slotId = widget.toItem.slot?.id;
    final toId = widget.toItem.to.id;
    if (slotId == null || slotId.isEmpty || toId.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      child: OutlinedButton.icon(
        onPressed: () => _openInviteMethod(work, toId, slotId, shortage),
        icon: const Icon(Icons.person_add_outlined, size: 16),
        // [DU530] 큰 글자에서 '부/족'으로 끊겼다 — 줄은 공백에서만 바꾼다. 글 원문 · 읽는 이름은 그대로(DU519 와 같은 방식).
        label: Text.rich(TextSpan(
          text: TextLayout.keepWords('인력 초대 ($shortage명 부족)'),
          semanticsLabel: '인력 초대 ($shortage명 부족)',
        )),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brand,
          side: const BorderSide(color: AppColors.brand),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  /// [R7-P1-2 DEVICE.1E.1 §6] 장기 공고의 부족 — 다음 경로를 말한다.
  ///
  ///   버튼이 아니라 안내다. 이 화면에서 초대를 열면 약속 범위(시작·종료)를
  ///   여기서 정하게 되고, 그건 이 다이얼로그가 갖지 않은 계약 정보다.
  ///   모집 재개·권한 우회는 하지 않는다 — 공고 카드의 게이트가 그대로
  ///   판단한다.
  Widget _buildLongTermShortageRoute(BuildContext context, int shortage) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_add_outlined,
              size: 16, color: AppColors.grey600),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '$shortage명이 더 필요해요. 장기 근무 초대는 근무 기간을 정해야 해서\n'
              '공고 카드의 ⋮ 메뉴 > 인력 초대에서 보낼 수 있어요.',
              style:
                  ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
          ),
        ],
      ),
    );
  }

  /// [R7-P1-2 DEVICE.1E.2] 갱신 중 — 실패가 아니다.
  ///
  ///   방금 한 처리는 성공했고, 정원만 다시 세는 중이다. `다시 시도` 를 두지
  ///   않는다 — 여기서 재시도를 권하면 도메인 처리를 다시 하라는 말로 읽힌다.
  ///   표시용 수치는 있으나 `FULL`·`부족`을 확정하지 않는다(출처가 canonical
  ///   이 아니다).
  Widget _buildCapacityPendingNotice(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: ResponsiveHelper.iconSize(context, 14),
            height: ResponsiveHelper.iconSize(context, 14),
            child: const CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.grey500),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Text(
              // [R7-P1-2 DEVICE.1E.2A] 여기에 `(충원 N)` 을 적고 있었다.
              //
              //   그 N 은 mutation 직후 화면이 손으로 다시 센 값이고,
              //   canonical 과 identity 규칙이 다르다 — wdId 충돌로 필요 12 에
              //   15 가 나올 수 있다고 직접 증명한 값이다. `갱신 중` 이라는
              //   말과 함께라도 현재 충원처럼 보여 줄 수 없다.
              //
              //   처리가 성공했다는 사실만 말한다. 숫자는 canonical 이
              //   도착한 뒤에 나온다.
              '처리를 반영했어요. 인력 현황을 다시 확인하는 중이에요.',
              style:
                  ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
          ),
        ],
      ),
    );
  }

  /// UNKNOWN을 없는 것처럼 지나가지 않는다 — ERROR != ZERO.
  Widget _buildCapacityUnknownNotice(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.grey600),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              _capacityLoading
                  ? '인력 현황을 확인하는 중이에요.'
                  : '인력 현황을 확인하지 못해 충원이 필요한지 알 수 없어요.\n다시 시도해 주세요.',
              style:
                  ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
          ),
          // [R7-P1-2 DEVICE.1E] 정원을 다시 읽는다.
          //
          //   여기는 `_loadApplicants` 를 불렀다. 그 함수는 지원서만 다시
          //   읽고 정원 map 은 건드리지 않는다 — 몇 번을 눌러도 이 배너는
          //   사라질 수 없었다. 실패한 것을 다시 하는 버튼이어야 한다.
          if (!_capacityLoading)
            TextButton(
              onPressed: _loadCapacity,
              child: const Text('다시 시도'),
            ),
        ],
      ),
    );
  }

  /// Day와 **같은** 초대 시트를 연다. 별도 초대 경로를 만들지 않는다.
  ///
  /// [R7-P1-CORR] 같은 모집 단위의 초대 시트는 하나만 뜬다. 두 개가 쌓이면
  /// 관리자는 같은 자리에 초대를 두 번 보낼 수 있다.
  Future<void> _openInviteMethod(
          WorkDetailModel work, String toId, String slotId, int shortage) =>
      ActionGuard.runVoid(
        ActionGuard.keyOf('inviteMethod', [toId, slotId, work.id]),
        () => _openInviteMethodInner(work, toId, slotId, shortage),
      );

  Future<void> _openInviteMethodInner(
      WorkDetailModel work, String toId, String slotId, int shortage) async {
    if (!mounted) return;
    final date = widget.toItem.slot?.date ??
        widget.initialDate ??
        widget.toItem.to.date;
    final choice = await DialogHelper.showSheet<String>(
      context,
      builder: (ctx) => InviteMethodSheet(
        workType: work.workType,
        date: date,
        startTime: work.startTime,
        endTime: work.endTime,
        shortage: shortage,
      ),
    );
    if (!mounted || choice == null) return;

    final businessId = widget.toItem.to.businessId;
    // [ISG2-REFRESH] 네 결과를 구분한다.
    //   성공 → `_hasChanges`(상위 카드·홈 전파) + 재조회
    //   취소 → 아무것도 하지 않는다(성공으로 보이게 하지 않는다)
    //   실패·응답 불명확 → 성공으로 세지 않되 **재조회는 한다**
    //     (쓰기가 실제로 들어갔을 수 있다 — 진실은 서버에서 다시 읽는다)
    var sheetSucceeded = false;
    InviteDialogResult? directResult;
    if (choice == 'availability') {
      await DialogHelper.showSheet<void>(
        context,
        isScrollControlled: true,
        builder: (ctx) => AvailableWorkersBottomSheet(
          onInviteSucceeded: () => sheetSucceeded = true,
          // [E1-W3·SHEET] 확인하지 못한 대상 — 성공으로 세지 않고 기억만 한다.
          onInviteUnconfirmed: (uid) {
            final t = InviteVerifyTarget(
                toId: toId, targetUid: uid, slotId: slotId);
            if (!_unconfirmedInviteTargets.contains(t)) {
              _unconfirmedInviteTargets.add(t);
            }
          },
          toId: toId,
          slotId: slotId,
          workDetailId: work.id,
          businessId: businessId,
          date: date,
          workType: work.workType,
          startTime: work.startTime,
          endTime: work.endTime,
          requiredCount: work.requiredCount,
          // [R7-4 C7] canonical 이 아니면 null — 0 으로 되접지 않는다.
          //   `workDetailId: work.id` 는 그대로 둔다. 서버
          //   `callableGetAvailableWorkers` 는 이 값을
          //   `workType_startTime_endTime`(또는 workType)으로 매칭한 뒤
          //   거기서 wdId 를 역산한다. canonicalId 를 넘기면 매칭에 실패해
          //   **첫 번째 업무로 폴백**한다 — 지금 값이 맞는 값이다.
          confirmedCount: _canonicalConfirmed,
        ),
      );
    } else if (choice == 'direct') {
      // Day와 같은 contextual 생성자 — 날짜·슬롯을 다시 고르게 하지 않는다.
      // [E1-AMBIGUOUS-INVITE] 다이얼로그는 sent / canceled / unconfirmed 로
      //   닫힌다. 예전 bool 에서는 저장 시도 뒤 응답이 불명확해도 사용자가
      //   닫으면 false(=취소)였다.
      final invited = await showDialog<InviteDialogResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => InviteWorkerDialog.contextual(
          toId: toId,
          businessId: businessId,
          businessName: widget.toItem.to.businessName,
          date: date,
          slotId: slotId,
          workType: work.workType,
          startTime: work.startTime,
          endTime: work.endTime,
        ),
      );
      directResult = invited;
    }
    if (!mounted) return;
    // [ISG2-REFRESH] 판단은 공용 식 하나가 한다.
    //   이 다이얼로그는 자기 목록만 다시 읽고 `_hasChanges` 를 세우지
    //   않았다 — 그래서 초대를 보내고 닫아도 상위 카드의 대기 수가
    //   그대로였다.
    // [E1-AMBIGUOUS-INVITE] 불명확하게 닫혔으면 대상 지원서를 다시 읽어
    //   **저장이 확인된 경우에만** 전파한다.
    final requested = choice == 'availability'
        ? inviteSheetOutcome(anySucceeded: sheetSucceeded)
        : inviteDialogOutcome(directResult);
    final resolved =
        await InviteSaveVerifier.resolve(requested, businessId: businessId);
    if (!mounted) return;
    InviteSaveVerifier.announceClose(resolved.check);
    final outcome = resolved.outcome;
    // [E1-W3] 확인하지 못한 대상은 남겨 두고, 아래 재조회(그리고 이후의
    //   성공한 재조회)에서 그 초대를 읽었을 때만 전파한다.
    final pending = requested.verify;
    if (pending != null &&
        resolved.check != InviteSaveCheck.saved &&
        !_unconfirmedInviteTargets.contains(pending)) {
      _unconfirmedInviteTargets.add(pending);
    }
    // [ISG2-REFRESH] 초대는 `_inviteChanged` 다 — 카드는 다시 그리되
    //   Home full refresh 는 깨우지 않는다(기록된 결정).
    if (outcome.propagate) _inviteChanged = true;
    if (outcome.reload) await _loadApplicants();
  }

  Widget _buildStatItem(BuildContext context, String label, int count, Color color, {bool compact = false}) {
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Container(
          width: ResponsiveHelper.spacing(context, 8),
          height: ResponsiveHelper.spacing(context, 8),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Text(
          '$label: ',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        ),
        Text(
          '$count명',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  /// 전체 선택 행
  Widget _buildSelectAllRow(BuildContext context, int pendingCount) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // [DU528] 왼쪽 묶음을 Wrap 으로 — 큰 글자에서 건수 칩이 아래 줄로 내려간다(이전 Row 는 오른쪽으로 넘쳤다).
          //   묶음이 한 줄에 들어가면 자리 · 간격 · 세로 가운데는 이전과 같다. 일괄 모드가 아니면 빈 칸(이전 Spacer 와 같다).
          Expanded(child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: ResponsiveHelper.spacing(context, 4),
              children: [
          if (_isBatchMode) ...[
            AppCheckbox(
              value: _selectAll,
              onTap: () => _toggleSelectAll(!_selectAll),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text('전체 선택', style: ResponsiveHelper.bodyStyle(context)),
            if (_selectedIds.isNotEmpty) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8),
                  vertical: ResponsiveHelper.spacing(context, 3),
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
                ),
                child: Text(
                  '${_selectedIds.length}건',
                  style: ResponsiveHelper.smallStyle(context, color: Theme.of(context).primaryColor),
                ),
              ),
            ],
          ],
          ])),
          // 일괄선택 토글 버튼
          Material(
            color: _isBatchMode
                ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                : AppColors.grey100,
            borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
            child: InkWell(
              onTap: () => setState(() {
                _isBatchMode = !_isBatchMode;
                if (!_isBatchMode) {
                  _selectedIds.clear();
                  _selectAll = false;
                } else {
                  // 다른 모드와 상호 배제
                  _isIdCardSelectMode = false;
                  _selectedIdCardUserIds.clear();
                }
              }),
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isBatchMode ? Icons.close : Icons.checklist,
                      size: ResponsiveHelper.iconSize(context, 14),
                      color: _isBatchMode
                          ? Theme.of(context).primaryColor
                          : AppColors.grey600,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      _isBatchMode ? '취소' : '일괄선택',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: _isBatchMode
                            ? Theme.of(context).primaryColor
                            : AppColors.grey600,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 빈 상태 — **조회에 성공했고 정말로 0명**일 때만 쓴다.
  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.people_outline,
      title: '지원자가 없습니다',
    );
  }

  /// [R7-P1-2] 최초 로드 실패 — 보여줄 명단이 없다.
  ///
  ///   `지원자가 없습니다`라고 쓰지 않는다. 지원자가 있는지 **확인하지 못했다.**
  ///   Day와 같은 어휘·같은 복구 수단을 쓴다(공통 위젯만 재사용, 복붙 아님).
  Widget _buildLoadErrorState() {
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
      child: AppEmptyState(
        icon: Icons.error_outline,
        iconColor: AppColors.error,
        title: '인력 현황을 불러오지 못했어요',
        subtitle: '지원자가 있는지 확인하지 못했습니다.',
        action: TextButton(
          onPressed: _isProcessing ? null : _loadApplicants,
          child: const Text('다시 시도'),
        ),
      ),
    );
  }

  /// [R7-P1-2.1] 확인된 권한 없음 — 고장이 아니다.
  ///
  ///   `불러오지 못했어요`(ERROR)도 `지원자가 없습니다`(ZERO)도 아니다.
  ///   둘 다 쓰면 관리자는 다시 시도하거나 지원자가 없다고 믿는다. 실제로는
  ///   볼 자격이 사라진 것이고, 다시 시도해서 열릴 문이 아니다.
  ///   그래서 retry loop 대신 닫기를 준다 — 권한은 이 화면이 되돌릴 수 없다.
  Widget _buildNoPermissionState() {
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
      child: const AppEmptyState(
        icon: Icons.lock_outline,
        iconColor: AppColors.grey400,
        title: '지원자 정보를 볼 권한이 없습니다',
        subtitle: 'TO 관리 권한이 있는 관리자에게 문의해주세요.',
      ),
    );
  }

  /// 권한 없음 상태의 하단 바 — 닫기만 남긴다.
  Widget _buildCloseOnlyBar(BuildContext context) {
    return AppModalFooter(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              _dialogResult,
            ),
            child: Text('닫기',
                style:
                    ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
          ),
        ],
      ),
    );
  }

  /// [R7-P1-2] 새로고침 실패 — 명단은 남기고 낡았다는 사실만 알린다.
  Widget _buildRefreshFailedBanner(BuildContext context) {
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
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_problem, size: 16, color: AppColors.warningDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '최신 정보를 불러오지 못했어요. 아래는 이전에 받은 내용입니다.',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.warningDark),
            ),
          ),
          TextButton(
            onPressed: _isProcessing ? null : _loadApplicants,
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }

  /// 지원자 목록: 별표시 먼저 → 주간 근무 적은 순 → 이름순
  List<Map<String, dynamic>> _sortedPending(List<Map<String, dynamic>> pending) {
    final sorted = List<Map<String, dynamic>>.from(pending);
    sorted.sort((a, b) {
      final aApp = a['application'] as ApplicationModel;
      final bApp = b['application'] as ApplicationModel;
      final aUser = a['user'] as UserModel?;
      final bUser = b['user'] as UserModel?;

      final aStarred = _starredIds.contains(aApp.id) ? 0 : 1;
      final bStarred = _starredIds.contains(bApp.id) ? 0 : 1;
      if (aStarred != bStarred) return aStarred.compareTo(bStarred);

      final aCount = _weeklyWorkCountMap[aUser?.uid ?? ''] ?? 0;
      final bCount = _weeklyWorkCountMap[bUser?.uid ?? ''] ?? 0;
      if (aCount != bCount) return aCount.compareTo(bCount);

      return (aUser?.name ?? '').compareTo(bUser?.name ?? '');
    });
    return sorted;
  }

  /// [DU528] [leading] 이 있으면(좁은 창) 통계 · 초대 · 전체 선택 줄을 같은 스크롤의 첫 항목으로 둔다 —
  ///   없으면 이전과 같은 위젯 그대로다(목록 여백 · 항목 변경 0).
  Widget _buildApplicantList(BuildContext context, List<Map<String, dynamic>> pending, List<Map<String, dynamic>> confirmed,
      {List<Widget> leading = const []}) {
    return SingleChildScrollView(
      padding: leading.isEmpty ? ResponsiveHelper.cardPadding(context) : null,
      child: _leadingThenList(context, leading, Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 대기 중 섹션 (별 표시 항목 상단 고정)
            if (pending.isNotEmpty) ...[
              _buildSectionHeader(context, '지원', pending.length, AppColors.warning),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ..._sortedPending(pending).asMap().entries.map((entry) =>
                  _buildApplicantCard(context, entry.value, entry.key + 1, isPending: true)),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            ],

            // [E2-INVITED-SEAT] 초대 섹션 — 승인 버튼 없이, 날짜별 명단과 같은 문구.
            if (_invites.isNotEmpty) ...[
              _buildSectionHeader(
                  context, '초대', _invites.length, AppColors.infoDark),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ..._invites.map((item) => _buildInviteRow(context, item,
                  capacity: _inviteRowCapacity)),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            ],

            // 확정 섹션
            if (confirmed.isNotEmpty) ...[
              _buildSectionHeader(context, '확정', confirmed.length, AppColors.success),
              // [NOSHOW-CONTRACT-GUARD] 근태를 몰라 발행을 멈춘 행이 있으면 이유·재시도.
              if (_contractAttendanceSuppressed) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                ContractAttendanceUnknownNotice(
                    onRetry: _retryContractAttendance,
                    retrying: _contractAttRetrying),
              ],
              Builder(builder: (context) {
                final requestableCount = _applicants.where((item) {
                  final app = item['application'] as ApplicationModel;
                  final user = item['user'] as UserModel?;
                  if ((app.status != AppStatus.confirmed && app.status != AppStatus.contractPending) || user == null) return false;
                  // [R7-P1-2 DEVICE.1E §7] 끝난 관계에 새 신분증을 요구하지
                  //   않는다. 온보딩이 남은 사람과 이미 끝난 사람은 다르다.
                  if (_isEndedRelation(app)) return false;
                  return IdCardHelper.isRequestable(_idCardStatusMap[user.uid] ?? 'none');
                }).length;
                // [R7-P1-5 §13] 1명이면 bulk UI를 세우지 않는다.
                //   한 사람에게 보낼 요청을 "일괄 처리" 패널로 감싸면, row에도
                //   같은 action이 있어 같은 일이 두 군데서 강하게 보인다.
                //   1명은 개인 카드의 action이 이미 처리한다.
                if (requestableCount < 2) return const SizedBox.shrink();
                return _buildIdCardRequestSection(context, requestableCount);
              }),
              Builder(builder: (context) {
                // [CSA-02] canManageContract 없는 사용자에게 계약서 일괄작성 버튼 숨김
                if (!_canManageContract()) return const SizedBox.shrink();
                final noContractCount = confirmed.where((item) {
                  final app = item['application'] as ApplicationModel;
                  final status = _contractStatusMap.statuses[app.id];
                  return status == null || status.isEmpty || status == 'voided';
                }).length;
                // [R7-P1-5 §13] 1명이면 개인 카드 action만 — bulk 패널 없음.
                if (noContractCount < 2) return const SizedBox.shrink();
                return _buildContractBatchSection(context, noContractCount);
              }),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ...confirmed.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                return _buildApplicantCard(context, item, index + 1, isPending: false);
              }),
            ],

            // [R7-P1-2 DEVICE.1E.1] 현재 인력이 아닌 관계를 **세 갈래**로 나눈다.
            //
            //   새 탭 체계를 만들지 않는다. 이 화면이 이미 쓰는
            //   `_buildSectionHeader` + 카드 목록 그대로, 자리만 나눈다.
            //   숨기지 않는 이유: 그 사람이 확정됐던 사실과 근무·계약·급여
            //   이력은 남아 있고 관리자가 거기로 갈 길이 필요하다.
            //
            //   순서는 급한 것부터다 — 할 일이 남은 쪽이 위다.

            // ① 만료 + 미결정 — 좌석은 비었지만 **결정이 남아 있다.**
            if (_decisionPending.isNotEmpty) ...[
              if (confirmed.isNotEmpty)
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              _buildSectionHeader(context, '계약 확인 필요',
                  _decisionPending.length, AppColors.warningDark, urgent: true),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ..._decisionPending.asMap().entries.map((entry) =>
                  _buildApplicantCard(context, entry.value, entry.key + 1,
                      isPending: false)),
            ],

            // ② 좌석 반납 — 자리는 비었지만 관계는 끝나지 않았다.
            if (_released.isNotEmpty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              _buildSectionHeader(
                  context, '좌석 반납', _released.length, AppColors.grey500),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ..._released.asMap().entries.map((entry) => _buildApplicantCard(
                  context, entry.value, entry.key + 1, isPending: false)),
            ],

            // ③ 결정까지 끝난 이력.
            if (_ended.isNotEmpty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              _buildSectionHeader(
                  context, '계약 종료', _ended.length, AppColors.grey500),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ..._ended.asMap().entries.map((entry) => _buildApplicantCard(
                  context, entry.value, entry.key + 1, isPending: false)),
            ],
          ],
        )),
      );
  }

  /// [DU528] 머리와 하단 사이 남은 칸(창이 내용만큼 줄어드는 성질은 그대로)에서 그 칸의 최대 높이를 [builder] 에 준다.
  Widget _measuredBody(Widget Function(BuildContext context, BoxConstraints box) builder) =>
      Flexible(child: LayoutBuilder(builder: builder));

  /// [DU532] 전체형 머리(보조 줄 포함) 아래 남는 칸의 최대 높이 — _headAndBody 의 재기 전용 사본이 배치 때마다 적는다.
  double _fullHeadBox = double.infinity;

  /// [DU532] 머리 + 본문 칸. [probe](업무별 창 · 권한 있음)가 아니면 이전과 같은 두 위젯 그대로다(narrow = false).
  ///   probe 면 '창 최대 높이 − 하단 − 전체형 머리'를 실측 한 가지로 먼저 얻는다: 전체형 머리의 그리지 않는 사본(Offstage —
  ///   배치만 · 그림 · 터치 · 읽는 이름 · 포커스 없음)을 같은 제약으로 배치하고 그 아래 남는 칸의 최대 높이를 받는다.
  ///   이 값은 실제 머리가 어느 모양이든 같다 — 보조 줄을 본문으로 내려도 바뀌지 않으므로 판정이 뒤집히지 않는다(순환 없음).
  ///   그 칸이 화면 높이의 60% 에 못 미치면(DU528 의 좁은 창 식 · 같은 값) narrow: 머리는 제목 · 닫기만, 보조 줄은 본문 첫 항목.
  ///   실제 머리 · 본문은 사본 다음에 배치 중 짓는다(LayoutBuilder · Stack 은 자식을 순서대로 배치) — 같은 프레임 · 글자 배율 상수 없음.
  List<Widget> _headAndBody(BuildContext context, ThemeData theme, bool probe,
      Widget Function(BuildContext context, BoxConstraints box, bool narrow) body) {
    if (!probe) return [_buildHeader(context, theme), _measuredBody((c, box) => body(c, box, false))];
    return [
      Flexible(
        child: Stack(children: [
          Offstage(
            child: ExcludeFocus(
              child: Column(children: [
                _buildHeader(context, theme),
                _measuredBody((_, ref) {
                  _fullHeadBox = ref.maxHeight;
                  return const SizedBox.shrink();
                }),
              ]),
            ),
          ),
          LayoutBuilder(builder: (context, _) {
            final narrow = _fullHeadBox < MediaQuery.sizeOf(context).height * 0.6;
            return Column(mainAxisSize: MainAxisSize.min, children: [
              _buildHeader(context, theme, dense: narrow),
              _measuredBody((c, box) => body(c, box, narrow)),
            ]);
          }),
        ]),
      ),
    ];
  }

  Widget _leadingThenList(BuildContext context, List<Widget> leading, Widget list) => leading.isEmpty
      ? list
      : Column(children: [...leading, Padding(padding: ResponsiveHelper.cardPadding(context), child: list)]);

  /// 그룹 모드: 업무별 섹션으로 나눈 지원자 목록
  Widget _buildGroupedApplicantList(BuildContext context) {
    final works = widget.toItem.workDetails;
    if (works.isEmpty) return _buildEmptyState();

    return SingleChildScrollView(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final work in works) ..._buildWorkSection(context, work),
        ],
      ),
    );
  }

  /// 업무 섹션 (헤더 + 대기 카드 + 확정 카드)
  List<Widget> _buildWorkSection(BuildContext context, WorkDetailModel work) {
    final workApplicants = _applicants.where((item) {
      final app = item['application'] as ApplicationModel;
      return _appMatchesWork(app, work);
    }).toList();

    // [E2-INVITED-SEAT] 초대만 있는 업무도 섹션을 세운다.
    final workInvites = _invites.where((item) => _appMatchesWork(
        item['application'] as ApplicationModel, work)).toList();

    if (workApplicants.isEmpty && workInvites.isEmpty) return [];

    final pending = workApplicants.where((item) =>
        (item['application'] as ApplicationModel).status == AppStatus.pending).toList();
    final confirmed = workApplicants.where((item) {
      final s = (item['application'] as ApplicationModel).status;
      return AppStatus.confirmedStatuses.contains(s);
    }).toList();

    return [
      // 업무 섹션 헤더
      Container(
        margin: EdgeInsets.only(
          bottom: ResponsiveHelper.spacing(context, 8),
          top: ResponsiveHelper.spacing(context, 12),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            WorkTypeIcon.buildWithBackground(
              iconString: work.workTypeIcon,
              backgroundColor: work.workTypeBackgroundColor,
              size: ResponsiveHelper.iconSize(context, 16),
              containerSize: ResponsiveHelper.spacing(context, 32),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work.workType,
                    style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey800)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${work.startTime}~${work.endTime}  ${work.formattedWage}',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                  ),
                ],
              ),
            ),
            if (pending.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '지원 ${pending.length}',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
                ),
              ),
            if (pending.isNotEmpty && confirmed.isNotEmpty)
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            if (confirmed.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '확정 ${confirmed.length}',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
      // 대기 섹션
      if (pending.isNotEmpty) ...[
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        ..._sortedPending(pending).asMap().entries.map((entry) =>
            _buildApplicantCard(context, entry.value, entry.key + 1, isPending: true, workOverride: work)),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
      ],
      // [E2-INVITED-SEAT] 초대 — 그룹 모드에는 업무별 canonical 정원이 없어
      //   자리 여부를 단정하지 않는다(UNKNOWN). 행은 상세로 이어진다.
      if (workInvites.isNotEmpty) ...[
        ...workInvites.map((item) => _buildInviteRow(context, item,
            capacity: InviteCapacityState.unknown)),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
      ],
      // 확정 섹션
      if (confirmed.isNotEmpty) ...[
        ...confirmed.asMap().entries.map((entry) =>
            _buildApplicantCard(context, entry.value, entry.key + 1, isPending: false, workOverride: work)),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
      ],
    ];
  }

  /// [E2-INVITED-SEAT] 초대 행이 말할 자리 상태.
  ///
  ///   `_capacityState` 의 closed 는 **공개 모집** 마감(기기 시계 판정 포함)이다.
  ///   공개 접수만 자동 마감된 단위의 초대는 기한까지 수락될 수 있는데, 이
  ///   화면은 그것을 가를 서버 투영(canonicalInviteEnded)을 갖고 있지 않다.
  ///   그래서 closed 를 `모집 종료` 로 단정하지 않고 UNKNOWN 으로 둔다 —
  ///   정확한 갈래는 날짜별 명단(서버 row)이 말한다.
  InviteCapacityState get _inviteRowCapacity {
    final c = _capacityState;
    return c == InviteCapacityState.closed ? InviteCapacityState.unknown : c;
  }

  /// [E2-INVITED-SEAT] 초대 한 줄 — [InviteRosterRow] 가 그린다(화면 없이 렌더 검증).
  Widget _buildInviteRow(
    BuildContext context,
    Map<String, dynamic> item, {
    required InviteCapacityState capacity,
  }) {
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    return InviteRosterRow(
      application: app,
      name: user?.displayName ?? app.applicantName ?? '근무자',
      capacity: capacity,
      onTap: user == null ? null : () => _showInvitedWorkerDetail(app, user),
    );
  }

  /// [E2-INVITED-SEAT] 초대받은 근로자 상세 — **승인 버튼 없이** 연다.
  ///   날짜별 명단 `_showInvitedWorkerDetail` 과 같은 호출이다.
  Future<void> _showInvitedWorkerDetail(
      ApplicationModel app, UserModel user) async {
    await WorkerDetailDialog.show(
      context: context,
      user: user,
      application: app,
      businessId: widget.toItem.to.businessId,
      isConfirmed: false,
      showApprovalButtons: false,
    );
    if (mounted) await _loadApplicants();
  }

  /// 매칭 헬퍼: app이 특정 work에 속하는지 확인
  bool _appMatchesWork(ApplicationModel app, WorkDetailModel work) {
    final wdId = app.workDetailId;
    if (wdId != null && wdId.isNotEmpty) {
      if (wdId == work.id) return true;
      if (wdId == work.workType) {
        return app.startTime == work.startTime && app.endTime == work.endTime;
      }
      return false;
    }
    return app.selectedWorkType == work.workType &&
        app.startTime == work.startTime &&
        app.endTime == work.endTime;
  }

  /// app에 대응하는 WorkDetailModel 반환 (그룹 모드용)
  WorkDetailModel? _getWorkForApp(ApplicationModel app) {
    for (final w in widget.toItem.workDetails) {
      if (_appMatchesWork(app, w)) return w;
    }
    return widget.work;
  }

  /// 신분증 일괄 요청 섹션 (confirmed_list_dialog와 동일한 패턴)
  Widget _buildIdCardRequestSection(BuildContext context, int requestableCount) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
        border: Border.all(color: AppColors.border),
      ),
      // [DU534] 좁은 창에서 안내와 버튼이 한 줄을 나눠 안내가 한 글자씩 끊겼다 — 날짜별 창과 같은 AdaptiveActionRow.
      child: AdaptiveActionRow(
        minRowWidth: 220,
        gap: ResponsiveHelper.spacing(context, 8),
        leading: Row(
        children: [
          Icon(Icons.badge, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey600),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              _isIdCardSelectMode
                  ? '${_selectedIdCardUserIds.length}명 선택됨'
                  // [R7-P1-4 §12] Day와 같은 수정 — canonical 의미는
                  //   `지금 요청할 수 있는 사람`(IdCardHelper.isRequestable)이다.
                  : TextLayout.keepWords('요청 가능 $requestableCount명'),
              semanticsLabel: _isIdCardSelectMode ? '${_selectedIdCardUserIds.length}명 선택됨' : '요청 가능 $requestableCount명',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary),
            ),
          ),
        ]),
        actions: [
          if (_isIdCardSelectMode && _selectedIdCardUserIds.isNotEmpty)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _batchRequestIdCard(),
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 6),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brand,
                    borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
                  ),
                  child: Text(
                    '요청하기',
                    style: ResponsiveHelper.smallStyle(context, color: Colors.white)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isIdCardSelectMode = !_isIdCardSelectMode;
                  if (!_isIdCardSelectMode) {
                    _selectedIdCardUserIds.clear();
                  } else {
                    _selectAllRequestableUsers();
                    // 다른 모드와 상호 배제
                    _isBatchMode = false;
                    _selectedIds.clear();
                    _selectAll = false;
                  }
                });
              },
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                decoration: BoxDecoration(
                  color: _isIdCardSelectMode ? AppColors.grey100 : Colors.transparent,
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
                ),
                child: Text(
                  _isIdCardSelectMode ? '취소' : '신분증 요청',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: _isIdCardSelectMode ? AppColors.grey700 : AppColors.brand,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 계약서 일괄작성 섹션 (확정자 중 계약 미작성자)
  Widget _buildContractBatchSection(BuildContext context, int noContractCount) {
    return Container(
      margin: EdgeInsets.only(
        top: ResponsiveHelper.spacing(context, 4),
        bottom: ResponsiveHelper.spacing(context, 4),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: AdaptiveActionRow(
        minRowWidth: 270,
        gap: ResponsiveHelper.spacing(context, 8),
        leading: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: ResponsiveHelper.iconSize(context, 18),
            color: AppColors.grey600,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              TextLayout.keepWords('계약서 미작성 $noContractCount명'),
              semanticsLabel: '계약서 미작성 $noContractCount명',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary),
            ),
          ),
        ]),
        actions: [
          if (_isContractBatchProcessing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            InkWell(
              onTap: _batchCreateContractsForConfirmed,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  border: Border.all(color: AppColors.brand, strokeAlign: BorderSide.strokeAlignOutside),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '계약서 일괄작성',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.brand)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 미요청자 전체 선택
  void _selectAllRequestableUsers() {
    _selectedIdCardUserIds.clear();
    for (final item in _applicants) {
      final app = item['application'] as ApplicationModel;
      final user = item['user'] as UserModel?;
      if ((app.status != AppStatus.confirmed && app.status != AppStatus.contractPending) || user == null) continue;
      // [R7-P1-2 DEVICE.1E §7] 끝난 관계는 전체 선택에도 들어가지 않는다.
      if (_isEndedRelation(app)) continue;

      final status = _idCardStatusMap[user.uid] ?? 'none';
      if (IdCardHelper.isRequestable(status)) {
        _selectedIdCardUserIds.add(user.uid);
      }
    }
  }

  /// 신분증 선택 토글
  void _toggleIdCardSelection(String uid) {
    setState(() {
      if (_selectedIdCardUserIds.contains(uid)) {
        _selectedIdCardUserIds.remove(uid);
      } else {
        _selectedIdCardUserIds.add(uid);
      }
    });
  }

  /// 일괄 신분증 요청
  Future<void> _batchRequestIdCard() async {
    if (_isProcessing) return; // 이중 탭 방지 — 중복 요청 전송 차단
    if (_selectedIdCardUserIds.isEmpty) return;
    setState(() => _isProcessing = true);
    try {
    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;
    if (currentUser == null) {
      ToastHelper.showError('로그인이 필요합니다');
      return;
    }

    // 선택된 사용자 정보 수집
    final targets = <Map<String, String>>[];
    for (final item in _applicants) {
      final app = item['application'] as ApplicationModel;
      final user = item['user'] as UserModel?;
      if (user == null || !_selectedIdCardUserIds.contains(user.uid)) continue;
      
      targets.add({
        'uid': user.uid,
        'name': user.name,
        'applicationId': app.id,
      });
    }

    final businessId = widget.toItem.to.businessId;
    final business = await _firestoreService.getBusinessById(businessId);

    if (!mounted) return;
    final successCount = await IdCardHelper.showBatchRequestDialog(
      context: context,
      firestoreService: _firestoreService,
      requester: {
        'uid': currentUser.uid,
        'name': currentUser.name,
      },
      business: {
        'id': businessId,
        'name': business?.name ?? '',
      },
      targets: targets,
    );

    if (!mounted) return;
    if (successCount > 0) {
      _hasChanges = true;

      // 상태 맵 업데이트 (요청 성공한 사용자들)
      setState(() {
        for (final uid in _selectedIdCardUserIds) {
          _idCardStatusMap[uid] = 'pending';
        }
        _isIdCardSelectMode = false;
        _selectedIdCardUserIds.clear();
        _isProcessing = false;
      });
    }
    } catch (e) {
      debugPrint('❌ [_batchRequestIdCard] 신분증 요청 실패: $e');
      if (mounted) ToastHelper.showError('신분증 요청 중 오류가 발생했습니다');
    } finally {
      if (mounted && _isProcessing) setState(() => _isProcessing = false);
    }
  }

  /// 섹션 헤더
  /// [UI-APPLICANTS-AND-INVITATIONS.2] 구획 제목은 중립색 한 가지 — 지원·확정·초대를 색 막대와 의미색으로
  ///   나누면 주황·초록·파랑이 겹쳤다(인력 현황 UI-1 과 같은 기준). [urgent] 는 결정이 남은 구획
  ///   ('계약 확인 필요')만 — 그 강조는 할 일이라서 남긴다. [color] 는 urgent 일 때만 쓴다.
  Widget _buildSectionHeader(BuildContext context, String title, int count, Color color,
      {bool urgent = false}) {
    final c = urgent ? color : AppColors.textSecondary;
    return Row(
      children: [
        if (urgent) ...[
          Container(
            width: ResponsiveHelper.spacing(context, 4),
            height: ResponsiveHelper.spacing(context, 20),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 2)),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        ],
        Text(
          '$title ($count명)',
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: c,
          ),
        ),
      ],
    );
  }

  /// 지원자 카드
  Widget _buildApplicantCard(BuildContext context, Map<String, dynamic> item, int index, {required bool isPending, WorkDetailModel? workOverride}) {
    final app = item['application'] as ApplicationModel;
    // ignore: unused_local_variable — 향후 확장용 (계약서 로직은 별도 메서드에서 _getWorkForApp 사용)
    final effectiveWork = workOverride ?? widget.work ?? _getWorkForApp(app);
    final user = item['user'] as UserModel?;
    final idCardStatus = _idCardStatusMap[user?.uid ?? ''] ?? 'none';
    // null = 로딩 전 / int = 로딩 완료 (0포함) → Wrap 조건부 포함으로 간격 오염 방지
    final weeklyCount = _weeklyWorkCountMap[user?.uid ?? ''];
    final isSelected = _selectedIds.contains(app.id);
    final isStarred = isPending && _starredIds.contains(app.id);
    final isNotificationTarget = widget.initialApplicationId != null && app.id == widget.initialApplicationId;

    Color cardBg = Colors.white;
    Color cardBorder = AppColors.border;
    if (isNotificationTarget) {
      // 알림 딥링크로 진입한 지원자 — 파란 강조 (isSelected보다 우선)
      cardBg = Theme.of(context).primaryColor.withValues(alpha: 0.08);
      cardBorder = Theme.of(context).primaryColor;
    } else if (isSelected) {
      cardBg = Theme.of(context).primaryColor.withValues(alpha: 0.05);
      cardBorder = Theme.of(context).primaryColor;
    } else if (isStarred) {
      cardBg = Colors.white;
      cardBorder = AppColors.border;
    } else if (!isPending) {
      // [R7-P1-2 DEVICE.1H §4] 확정은 완료된 사실 — 낮은 강조.
      //
      //   카드 전체 초록 tint 위에 초록 배지·초록 섹션 머리말이 겹쳐 같은
      //   사실을 세 번 말했다(D0: 반복 강조 축소 · 행당 강한 강조 제한 ·
      //   완료 정보 낮은 강조). tint 를 테두리로 낮춘다 — 배지 글자는
      //   그대로 둔다(상태를 색에만 의존하지 않는다).
      // [UI-APPLICANTS-AND-INVITATIONS.2] '확정' 구획 제목이 이미 말한다 — 행마다 초록 테두리로 반복하지 않는다.
      cardBorder = AppColors.border;
    }

    // [R7-P1-2 DEVICE.1H.1] 표면은 `ApplicantRowSurface` 가 그린다 — 실제로
    //   렌더해 확인할 수 있어야 하기 때문이다. 강조 색 규칙은 이 화면이 그대로
    //   갖는다(알림 딥링크 강조·선택 alpha 가 홈 일자별과 다르다 — 통합하면
    //   한쪽 모양이 바뀐다).
    return ApplicantRowSurface(
      background: cardBg,
      border: cardBorder,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isPending
              ? (_isBatchMode
                  ? () => _toggleSelection(app.id)
                  : () => _showApplicantDetail(item))
              : () => _showApplicantDetail(item),
          borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 10),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 신분증 선택모드 (확정자 전용)
                if (!isPending) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isIdCardSelectMode ? ResponsiveHelper.spacing(context, 28) : 0,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    child: _isIdCardSelectMode
                        ? Padding(
                            padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
                            // [R7-P1-2 DEVICE.1E §7] 끝난 관계에는 새 신분증을
                            //   요청하지 않는다 — 선택 자체를 만들지 않는다.
                            child: IdCardHelper.isRequestable(idCardStatus) &&
                                    !_isEndedRelation(app)
                                ? AppCheckbox(
                                    value: _selectedIdCardUserIds.contains(user?.uid ?? ''),
                                    onTap: () => _toggleIdCardSelection(user?.uid ?? ''),
                                    activeColor: AppColors.brand,
                                    size: ResponsiveHelper.iconSize(context, 20),
                                  )
                                : AppCheckbox(
                                    value: true,
                                    enabled: false,
                                    size: ResponsiveHelper.iconSize(context, 20),
                                  ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],

                // 정보 영역 (전체 너비 사용)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1줄: 순번 + 이름 + 성별·나이 | 배지/별
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                // 일괄선택 모드 선택 아이콘 (슬라이드인)
                                if (isPending) ...[
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: _isBatchMode ? ResponsiveHelper.spacing(context, 26) : 0,
                                    clipBehavior: Clip.hardEdge,
                                    decoration: const BoxDecoration(),
                                    child: _isBatchMode
                                        ? Padding(
                                            padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 6)),
                                            child: AppCheckbox(
                                              value: isSelected,
                                              size: ResponsiveHelper.iconSize(context, 20),
                                            ),
                                          )
                                        : null,
                                  ),
                                ],
                                Text(
                                  '$index.',
                                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey400)
                                      .copyWith(fontWeight: FontWeight.w700),
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 5)),
                                Flexible(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        // [UI-APPLICANTS-AND-INVITATIONS.2] 긴 이름을 한 줄 말줄임으로 숨기지 않는다 —
                                        //   두 줄까지 보이고 그 뒤에만 줄인다(동명이인 구분은 옆 인력번호가 한다).
                                        child: Text(
                                          user?.name ?? app.applicantName ?? '이름 없음',
                                          style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w700),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      // [R7-PRE1A.1] 번호를 성별·나이와 같은 보조 줄에 둔다.
                                      //   이름만 있는 목록에서는 동명이인 두 줄이 똑같아 보인다.
                                      // [DIALOG-VISUAL-CLOSE] 보조 줄은 짧은 고정 폭으로 둔다.
                                      //   둘 다 Flexible 이면 남는 몫을 서로 돌려주지 않아 이름이
                                      //   행의 1/4 로 묶였다(Pixel 5: `QA 지…` 두 명을 구별 못 함).
                                      if (PersonLabel.secondary(
                                            user?.personNo,
                                            '${user?.gender ?? ''}'
                                            '${user?.age != null ? ' · ${user?.age}세' : ''}',
                                          ).isNotEmpty) ...[
                                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                        Text(
                                          '(${PersonLabel.secondary(
                                            user?.personNo,
                                            '${user?.gender ?? ''}'
                                            '${user?.age != null ? ' · ${user?.age}세' : ''}',
                                          )})',
                                          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                                          maxLines: 1,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // [DIALOG-VISUAL-CLOSE] 지원 시각은 2줄로 내렸다(아래 Wrap 첫 칸).
                          //   이 줄에서 `Expanded(이름)` 과 1:1 로 폭을 나눠 이름을 반으로 묶었다.
                          if (isPending) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            GestureDetector(
                              onTap: () async {
                                final nowStarred = !_starredIds.contains(app.id);
                                // Optimistic update — 즉시 반영해 이중 탭 시 방향 뒤집힘 방지
                                setState(() {
                                  if (nowStarred) {
                                    _starredIds.add(app.id);
                                  } else {
                                    _starredIds.remove(app.id);
                                  }
                                });
                                try {
                                  await _firestoreService.updateApplicationFields(
                                    app.id,
                                    {'isStarred': nowStarred},
                                  );
                                } catch (e) {
                                  // 실패 시 UI 롤백
                                  if (mounted) {
                                    setState(() {
                                      if (nowStarred) {
                                        _starredIds.remove(app.id);
                                      } else {
                                        _starredIds.add(app.id);
                                      }
                                    });
                                    ToastHelper.showError('별 표시 저장에 실패했습니다');
                                  }
                                }
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  left: ResponsiveHelper.spacing(context, 6),
                                  top: ResponsiveHelper.spacing(context, 10),
                                  bottom: ResponsiveHelper.spacing(context, 10),
                                ),
                                child: Icon(
                                  isStarred ? Icons.star_rounded : Icons.star_border_rounded,
                                  size: ResponsiveHelper.iconSize(context, 18),
                                  color: isStarred ? AppColors.amber : AppColors.grey300,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 5)),

                      // 2줄: 신뢰도 · 전화 · 주간횟수 · 평점
                      Wrap(
                        spacing: ResponsiveHelper.spacing(context, 5),
                        runSpacing: ResponsiveHelper.spacing(context, 3),
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // [R7-P1-2 DEVICE.1H.1] 큰 글자에서 넘치던 칸 — Wrap 안이라 줄바꿈된다.
                          Text(
                            _relationTimeLabel(app),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
                          ),
                          if (user?.effectivePhone != null && (user?.effectivePhone ?? '').isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.phone, size: ResponsiveHelper.iconSize(context, 11), color: AppColors.grey400),
                                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                Text(
                                  FormatHelper.formatPhone(user?.effectivePhone ?? ''),
                                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                                ),
                              ],
                            ),
                          if (user != null && user.recentNoShowCount > 0)
                            _buildNoShowBadge(context, user.recentNoShowCount),
                          if (weeklyCount != null)
                            _buildWeeklyCountBadge(context, weeklyCount),
                          if (user != null && user.averageRating > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, size: ResponsiveHelper.iconSize(context, 12), color: AppColors.amber),
                                SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                                Text(
                                  user.averageRating.toStringAsFixed(1),
                                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                                ),
                              ],
                            ),
                        ],
                      ),

                      // 3줄: 배지 (리뷰·계약·신분증) — 확정자 전용
                      if (!isPending) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                        Wrap(
                          spacing: ResponsiveHelper.spacing(context, 4),
                          runSpacing: ResponsiveHelper.spacing(context, 3),
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            // [R7-P1-4 §11] 리뷰 배지 제거 — Day와 같은 이유.
                            //   확정자 전원에게 `리뷰미작성`이 붙어 근무 전
                            //   확정자·NO_SHOW-only에게도 없는 업무를 만들었고,
                            //   자격을 고쳐도 충원 판단에 쓰이는 정보가 아니다.
                            // [R7-P1-2 DEVICE.1E] lifecycle 을 먼저 말한다.
                            //   이 사람에 대한 나머지 배지는 전부 그 다음이다 —
                            //   끝난 관계인지 모른 채 `계약서 작성 필요`부터
                            //   읽으면 관리자는 없는 할 일을 먼저 본다.
                            // [R7-P1-2 DEVICE.1E.1] 라벨은 canonical 조합이
                            //   정한다 — 화면이 날짜 조건을 다시 쓰지 않는다.
                            if (staffingRelationLabel(app, _workApplicantsNow())
                                case final label?)
                              _buildRelationBadge(context, label,
                                  urgent: staffingRelationOf(app, _workApplicantsNow())
                                      .decisionPending),
                            _buildContractBadge(context, app,
                                isEnded: _isEndedRelation(app)),
                            // [CORRECTION-R7-ENDED-ID-REUPLOAD-ACTION-COPY]
                            //
                            //   종료된 관계에 `신분증 재요청 필요` 가 남아
                            //   있었다. 그 사람에게는 개별·선택·일괄 요청
                            //   경로가 모두 없다 — **행동이 없는데 행동을
                            //   요구하는 강조**만 남은 것이다.
                            //
                            //   요구형(none/expired/rejected = isRequestable)
                            //   만 내린다. 제출·승인 같은 **기록**은 그대로
                            //   둔다 — 그것은 과거 관계의 사실이고, 급여·
                            //   계약 정리에 필요한 정보다.
                            //   공용 IdCardHelper 문구를 전역으로 바꾸지 않는다.
                            if (!(_isEndedRelation(app) &&
                                IdCardHelper.isRequestable(idCardStatus)))
                              IdCardHelper.buildStatusBadge(
                                  context, idCardStatus),
                          ],
                        ),
                      ],

                      // 자기소개
                      if (app.applicationMessage?.isNotEmpty == true) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 8),
                            vertical: ResponsiveHelper.spacing(context, 4),
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.grey50,
                            borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 6)),
                          ),
                          child: Text(
                            app.applicationMessage!,
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],

                      // 장기 근무 정보
                      if (widget.toItem.to.isLongTerm && app.isLongTermApplication && app.workPeriodDisplay.isNotEmpty) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 5)),
                        Row(
                          children: [
                            Icon(
                              Icons.date_range,
                              size: ResponsiveHelper.iconSize(context, 12),
                              color: app.desiredStartDate != null ? Theme.of(context).primaryColor : AppColors.grey500,
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Flexible(
                              child: Text(
                                app.desiredStartDate != null
                                    // [R7-P1-2 DEVICE.1] 근무 약속 날짜는 KST 달력이다.
                                    ? '희망: ${FormatHelper.formatDateShort(app.desiredStartDate!)}~'
                                        '${app.workEndDate != null ? " (${FormatHelper.formatDateShort(app.workEndDate!)}까지)" : ""}'
                                    : '장기: ${app.workPeriodDisplay}',
                                style: ResponsiveHelper.smallStyle(
                                  context,
                                  color: app.desiredStartDate != null ? Theme.of(context).primaryColor : AppColors.grey600,
                                ).copyWith(
                                  fontWeight: app.desiredStartDate != null ? FontWeight.w600 : FontWeight.normal,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],

                      // 확정자 액션 버튼 (파트변경 / 계약서 작성 / 확정취소 or 고정근무 관리)
                      if (!isPending && !_isBatchMode) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        _actionRow(
                          context,
                          primary: [
                            // [CROSS-DOMAIN-R5.3A] '파트변경' CTA 제거.
                            //   관리자 혼자 확정된 약속을 덮어쓰던 경로다.
                            //   업무를 옮기는 일은 제안이고 근로자가 수락해야
                            //   성립한다 — '다른 업무 제안'이 준비되면 돌아온다.
                            // 계약 미작성 시 개별 작성 버튼 — [CSA-02] canManageContract 필수
                            // [R7-P1-2 DEVICE.1E §7] 끝난 관계에는 **현재 근무
                            //   계약서를 새로 만들라고 하지 않는다**. 이 버튼은
                            //   지금부터의 근로계약을 만드는 경로이고, 5일 전
                            //   종료된 약속에 그것을 붙이면 성립할 수 없는
                            //   약속을 권하는 것이다.
                            //   (이미 근무한 기간에 대한 사후 계약 정비가
                            //    필요한지는 이 Phase 가 정할 정책이 아니다 —
                            //    [OPEN-R7-ENDED-CONTRACT-REMEDIATION-POLICY])
                            if (_canManageContract() &&
                                !_isEndedRelation(app) &&
                                _needsContractIssue(app))
                              _buildActionButton(
                                context,
                                label: '계약서 작성',
                                icon: Icons.description_outlined,
                                bgColor: AppColors.brand,
                                textColor: Colors.white,
                                filled: true,
                                onTap: () => _createContractForConfirmedUser(item),
                              ),
                          ],
                          secondary: [
                            // [B-2] 장기근무자는 첫 출근 전에도 고정근무 관리 가능
                            if (widget.toItem.to.isLongTerm)
                              _buildActionButton(
                                context,
                                label: '고정근무 관리',
                                icon: Icons.settings,
                                bgColor: Colors.transparent,
                                textColor: AppColors.textSecondary,
                                // [B-3] item 전달 → 해당 근무자 uid로 자동 포커스
                                onTap: () => _openFixedWorkerManagement(item),
                              )
                            // [BUG-CANCEL-01] 근무 이력 있는 단기 확정자 취소 버튼 숨김
                            else if (_canCancelConfirmation(app))
                              _buildActionButton(
                                context,
                                label: '확정취소',
                                icon: Icons.cancel_outlined,
                                bgColor: Colors.transparent,
                                textColor: AppColors.errorDark,
                                onTap: () => _cancelConfirmation(item),
                              ),
                          ],
                        ),
                        // [CROSS-DOMAIN-R5.3E.2] 확정 근로자 업무 변경 제안.
                        //
                        //   제안을 보냈다고 근무가 바뀌지 않는다. 그래서 이 줄은
                        //   확정 뱃지·스케줄을 건드리지 않고, 보낸 뒤에는
                        //   '변경 확인 대기'로만 바뀐다 — B로 확정된 것처럼
                        //   보이면 관리자가 실제 인력 상황을 잘못 읽는다.
                        if (!widget.toItem.to.isLongTerm &&
                            _canManageTo() &&
                            _canProposeReassignment(app)) ...[
                          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                          Align(
                            alignment: Alignment.centerRight,
                            child: _pendingReassignmentOf(app) != null
                                ? _buildActionButton(
                                    context,
                                    label: '변경 확인 대기',
                                    icon: Icons.hourglass_top,
                                    bgColor: Colors.transparent,
                                    textColor: AppColors.warningDark,
                                    onTap: () => _cancelReassignment(app),
                                  )
                                : _buildActionButton(
                                    context,
                                    label: '근무 변경 제안',
                                    icon: Icons.swap_horiz,
                                    bgColor: Colors.transparent,
                                    textColor: AppColors.textSecondary,
                                    onTap: () =>
                                        _showConfirmedReassignmentSheet(item),
                                  ),
                          ),
                        ],
                      ],

                      // 대기 중 액션 버튼 (파트변경 / 거절 / 승인)
                      // [4J.0B] 거절: 항상 허용(PENDING 정리 목적), 승인: canApprovePending만 허용
                      // isClosed 통합 가드 제거 — isManualClosed TO에서도 거절 허용하기 위함
                      if (isPending && !_isBatchMode &&
                          _canManageTo()) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        _actionRow(
                          context,
                          secondary: [
                            // [CROSS-DOMAIN-R5.3A] '파트변경' CTA 제거 (대기자 경로).
                            //   PENDING 지원자의 지원 조건을 동의 없이 덮어썼다.
                            // [CROSS-DOMAIN-R5.3B] 그 자리를 '다른 업무 제안'이 대신한다.
                            //   관리자는 바꾸지 않는다 — 제안하고, 근로자가 고른다.
                            //   제안할 다른 업무가 실제로 있을 때만 띄운다.
                            if (_offerableWorkDetails(app).isNotEmpty) ...[
                              _buildActionButton(
                                context,
                                label: '다른 업무 제안',
                                icon: Icons.swap_horiz,
                                bgColor: Colors.transparent,
                                textColor: AppColors.textSecondary,
                                onTap: () => _showAlternativeWorkOfferSheet(item),
                              ),
                            ],
                            _buildActionButton(
                              context,
                              label: '거절',
                              icon: Icons.close,
                              bgColor: Colors.transparent,
                              textColor: AppColors.errorDark,
                              onTap: () => _rejectApplication(item),
                            ),
                          ],
                          primary: [
                            if (widget.toItem.to.canApprovePending)
                              _buildActionButton(
                                context,
                                label: '확정',
                                icon: Icons.check,
                                bgColor: AppColors.brand,
                                textColor: Colors.white,
                                filled: true,
                                onTap: () => _approveApplication(item),
                              ),
                          ],
                        ),
                        // [4J.1] FULL/TIME_EXPIRED 힌트 — 승인 버튼이 숨겨진 이유 안내
                        if (!widget.toItem.to.canApprovePending) ...[
                          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            widget.toItem.to.isFull
                                ? '정원이 충족된 공고입니다. 추가 확정이 제한됩니다.'
                                : '기간이 만료된 공고입니다. 추가 확정이 제한됩니다.',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.grey500),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [UI-APPLICANTS-AND-INVITATIONS.2] 행 버튼 줄 — 보조·위험은 왼쪽(줄을 넘길 수 있음), 주요 채움은 오른쪽 끝.
  ///   인력 현황(_actionRow)과 같은 배치. 보조가 없어도 주요 버튼 자리는 같다.
  Widget _actionRow(BuildContext context,
      {List<Widget> secondary = const [], List<Widget> primary = const []}) {
    // [DU527a] 인력 현황(O002 · DU517)과 같은 배치 — 두 묶음이 한 줄에 들어가면 보조 왼쪽 · 주요 오른쪽 끝,
    //   안 들어가면 묶음째 아래 줄로 내린다(오른쪽 맞춤). 이전 Row[Expanded(보조) · 주요]는 주요가 넓으면 보조 칸이 눌렸다.
    final secondaryWrap = Wrap(
      spacing: ResponsiveHelper.spacing(context, 4),
      runSpacing: ResponsiveHelper.spacing(context, 4),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: secondary,
    );
    if (primary.isEmpty) {
      return SizedBox(width: double.infinity, child: secondaryWrap);
    }
    return SizedBox(
      width: double.infinity,
      child: OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        spacing: ResponsiveHelper.spacing(context, 8),
        overflowSpacing: ResponsiveHelper.spacing(context, 6),
        overflowAlignment: OverflowBarAlignment.end,
        children: [
          secondaryWrap,
          Wrap(
            spacing: ResponsiveHelper.spacing(context, 8),
            runSpacing: ResponsiveHelper.spacing(context, 6),
            alignment: WrapAlignment.end,
            children: primary,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    final effectiveBg = filled ? bgColor : Colors.transparent;
    final effectiveText = filled ? Colors.white : textColor;
    return Material(
      color: effectiveBg,
      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
        child: Container(
          // [DU527a] 받는 자리 — 인력 현황(O002 _actionButton)과 같은 여백: 주요 16×15.5 · 글자 행동 12×14.
          //   화면 폭 배율을 곱하지 않는다(곱하면 390 미만에서 48 아래로 내려간다). 모양 · 글자 크기는 그대로.
          // [DU527a r2] 이 창의 글자 줄 높이는 19 라 여백만으로는 글자 행동이 47 이었다(r1 TA) — 최소 높이 48 을 명시한다.
          //   alignment 는 주지 않는다(Wrap 안에서 가로로 늘어난다 — O002 :2492 주석). 주요(50)는 그대로.
          constraints: filled ? null : const BoxConstraints(minHeight: 48),
          padding: EdgeInsets.symmetric(
            horizontal: filled ? 16 : 12,
            vertical: filled ? 15.5 : 14,
          ),
          // [UI-APPLICANTS-AND-INVITATIONS.2] 채움이 아닌 버튼(보조·위험)은 테두리 없이 글자로 —
          //   반복 명단에서 상자 세 개가 모두 시선을 끌었다(UI-1 사용자 의견).
          decoration: null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: ResponsiveHelper.iconSize(context, 13), color: effectiveText),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Text(
                label,
                style: ResponsiveHelper.smallStyle(context, color: effectiveText)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

/// 리뷰 작성 여부 배지

  /// [R7-P1-2 DEVICE.1E.1] 근무 관계의 primary lifecycle 배지.
  ///
  ///   문구는 `staffingRelationLabel` 이 정한다 — FixedWorker 관리·Home
  ///   만료 화면이 이미 쓰는 말이다. 같은 사람의 같은 사실을 화면마다
  ///   다른 단어로 부르지 않는다.
  ///
  ///   [urgent] 는 **할 일이 남은** 상태다(만료+미결정). 끝난 이력과 같은
  ///   회색으로 적으면 그 일이 없는 것처럼 읽힌다.
  Widget _buildRelationBadge(BuildContext context, String label,
      {bool urgent = false}) {
    final color = urgent ? AppColors.warningDark : AppColors.grey600;
    final bg = urgent ? AppColors.warningBg : AppColors.grey100;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(context, color: color)
            .copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

/// 계약서 상태 배지 (확정자 전용)
  Widget _buildContractBadge(BuildContext context, ApplicationModel app,
      {bool isEnded = false}) {
    final appId = app.id;
    final status = _contractStatusMap.statuses[appId];
    final String label;
    final Color color;
    final Color bgColor;
    // [REISSUE-RECOVERY] 조회하지 못한 건은 **모른다고 말한다.**
    //   `계약서 작성 필요`로 적으면 있는 계약을 또 만들러 간다.
    if (_contractStatusMap.isUnresolved(appId)) {
      label = '계약 상태 확인 불가';
      color = AppColors.grey600;
      bgColor = AppColors.grey100;
    } else if (status == null || status.isEmpty) {
      // [R7-P1-6 §14] 계약 미작성은 실패가 아니라 **지금 할 수 있는 다음 일**이다.
      //   red는 NO_SHOW·무효처럼 실제로 잘못된 것에 남긴다.
      // [R7-P1-2 DEVICE.1E §7] 다만 끝난 관계에서는 그 `다음 일`이 없다.
      //   같은 사실(계약서가 없다)을 **요구**가 아니라 **기록**으로 적는다.
      // [DIALOG-VISUAL-CLOSE] `작성 필요`는 버튼과 같은 판정(_needsContractIssue)일 때만.
      //   노쇼·결근 근무일·좌석 반납에도 붙어 할 수 없는 일을 권했다(Pixel 5 10-23 관찰).
      if (isEnded) {
        label = '계약서 미작성';
      } else if (_needsContractIssue(app)) {
        label = '계약서 작성 필요';
      } else if (app.isContractIssuable &&
          _contractBlockedAppIds == null &&
          ContractAttendanceGate.attendanceDocId(app) != null) {
        label = '근태 확인 필요';
      } else {
        label = '계약 대상 아님';
      }
      final actionable = label == '계약서 작성 필요';
      color = actionable ? AppColors.warningDark : AppColors.grey600;
      bgColor = actionable ? AppColors.warningBg : AppColors.grey100;
    } else {
      switch (status) {
        case 'pending_employer':
          label = '관리자서명';
          color = AppColors.warningDark;
          bgColor = AppColors.warningBg;
        case 'pending_worker':
          label = '서명대기';
          color = AppColors.warningDark;
          bgColor = AppColors.warningBg;
        // [R7-P1-6 §14] 끝난 것은 참고 정보 — gray. green은 `확정`에 쓴다.
        case 'completed':
          label = '계약완료';
          color = AppColors.grey600;
          bgColor = AppColors.grey100;
        case 'voided':
          label = '무효';
          color = AppColors.error;
          bgColor = AppColors.errorBg;
        default:
          label = '계약중';
          color = AppColors.grey600;
          bgColor = AppColors.grey100;
      }
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(context, color: color)
            .copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  // 노쇼 팩트 배지 (신뢰도 점수 대체 — 5A.2A)
  Widget _buildNoShowBadge(BuildContext context, int count) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: ResponsiveHelper.iconSize(context, 10),
              color: AppColors.error),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            '최근 90일 노쇼 $count회',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.error).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 이번 주 근무 횟수 배지 — 참고 정보다.
  ///
  /// null = 데이터 미로드, 0 = 이번 주 미근무.
  /// [R7-P1-PRODUCT §13] 색으로 등급을 매기지 않는다. 숫자가 사실이고,
  /// 그 사실을 어떻게 볼지는 관리자가 정한다.
  Widget _buildWeeklyCountBadge(BuildContext context, int? count) {
    if (count == null) return const SizedBox.shrink();

    final Color color;
    final Color bgColor;
    final IconData icon;

    // [R7-P1-PRODUCT §13] green/blue/orange 4단계 의미색을 쓰고 있었다.
    //
    //   주N회는 **빈도 사실**이지 상태가 아니다. 색 계약(§14)에 비춰 보면
    //   셋 다 오용이다 — green은 확정/성공, blue는 action/selection,
    //   orange는 지금 처리 가능한 미완료다. 주2회가 성공은 아니고,
    //   주3회가 누를 것도 아니며, 주5회가 처리할 일도 아니다.
    //
    //   한 카드에 strong color가 여러 개면 정작 눌러야 하는 것이 묻힌다.
    //   숫자 자체가 이미 정보를 담으므로 색을 빼고 참고 정보로 내린다.
    color = AppColors.grey600;
    bgColor = AppColors.grey100;
    icon = count == 0
        ? Icons.calendar_today_outlined
        : Icons.calendar_today;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 10), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text(
            '주$count회',
            style: ResponsiveHelper.tinyStyle(context, color: color).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 지원 시간 포맷
  /// [INVITE-TIME-COPY] 초대로 들어온 사람은 초대한 시각(`초대 N분 전`). 기록이 없으면 `초대` 만.
  String _relationTimeLabel(ApplicationModel app) {
    if (app.invitedAt != null) {
      return _formatAppliedTime(app.invitedAt!).replaceFirst('지원', '초대');
    }
    if (app.invitedBy != null) return '초대';
    return _formatAppliedTime(app.appliedAt);
  }

  String _formatAppliedTime(DateTime appliedAt) {
    final now = _workApplicantsNow();
    final diff = now.difference(appliedAt);

    // [R7-P1-2 DEVICE.1H §4] 상대 표기에도 같은 이름을 붙인다.
    //   7일 경과 시의 절대 표기만 `지원 …` 이고 그 전까지는 `4일 전` 이어서,
    //   같은 자리의 같은 값이 어느 날 갑자기 이름을 얻었다.
    if (diff.isNegative || diff.inMinutes < 1) {
      return '지원 방금 전';
    }
    if (diff.inMinutes < 60) {
      return '지원 ${diff.inMinutes}분 전';
    } else if (diff.inHours < 24) {
      return '지원 ${diff.inHours}시간 전';
    } else if (diff.inDays < 7) {
      return '지원 ${diff.inDays}일 전';
    } else {
      // [R7-P1-2 DEVICE.1E §8] 이 절대시각에는 **이름이 없었다**.
      //
      //   `3일 전`은 무엇의 3일 전인지 자명하지만, 7일이 지나 형식이
      //   `09/15 00:00`으로 바뀌는 순간 그 숫자가 지원인지 확정인지
      //   계약인지 알 수 없어진다. 실기기 화면의 라벨 없는 timestamp가
      //   그것이다. 뜻을 지어내지 않고 **실제 이벤트 이름**을 붙인다.
      //
      //   그리고 KST로 말한다. appliedAt은 INSTANT이므로 상대 표기
      //   (`3일 전`)는 timezone과 무관하지만, 절대 표기는 아니다 —
      //   DEV 실측 09/15 09:00 KST가 UTC 기기에서 `09/15 00:00`으로 보였다.
      return '지원 ${FormatHelper.formatDateShort(appliedAt)} '
          '${FormatHelper.formatTime(appliedAt)}';
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // [CROSS-DOMAIN-R5.3B] 다른 업무 제안
  //
  //   R5.3A에서 '파트변경'을 얼린 이유는 그것이 **근로자가 동의한 적 없는 조건**
  //   으로 지원서를 덮어썼기 때문이다. 대체 경로는 덮어쓰지 않는다:
  //   같은 슬롯의 다른 업무(B)로 **새 제안**을 만들고, 원 지원(A)은 근로자가
  //   수락하는 순간에만 서버가 같은 트랜잭션에서 접는다.
  //
  //   그래서 이 화면의 문구는 "업무를 바로 변경합니다"가 될 수 없다.
  //   관리자가 하는 일은 제안을 보내는 것까지다.
  // ═══════════════════════════════════════════════════════════════════════════

  /// 이 지원자에게 제안할 수 있는 다른 업무들 — 판정은 공용 시트가 갖는다.
  List<WorkDetailModel> _offerableWorkDetails(ApplicationModel app) =>
      AlternativeWorkOfferSheet.offerableFrom(
          widget.toItem.workDetails, _getWorkForApp(app));

  /// 이 업무에 지금 확정된 인원 수 — 화면에 이미 로드된 지원서에서 센다.
  int _confirmedCountForWork(WorkDetailModel work) {
    return _applicants.where((item) {
      final a = item['application'] as ApplicationModel;
      return _appMatchesWork(a, work) &&
          AppStatus.confirmedStatuses.contains(a.status);
    }).length;
  }

  /// [R7-P1-CORR] 대체 업무 제안은 제안 문서 + 알림을 만든다 — 두 번 실행되면
  ///   같은 근로자가 같은 제안을 두 통 받는다. 시트 await 구간에 두 번째 탭이
  ///   통과할 수 있었으므로 single-flight로 감싼다.
  Future<void> _showAlternativeWorkOfferSheet(Map<String, dynamic> item) {
    final app = item['application'] as ApplicationModel;
    return ActionGuard.runVoid(
      ActionGuard.keyOf('altWorkOffer', [app.id]),
      () => _showAlternativeWorkOfferSheetInner(item),
    );
  }

  Future<void> _showAlternativeWorkOfferSheetInner(
      Map<String, dynamic> item) async {
    if (_isProcessing) return;
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final workerName = _personLabelOf(user, '지원자');
    final currentWork = _getWorkForApp(app);
    final candidates = _offerableWorkDetails(app);
    if (candidates.isEmpty) {
      ToastHelper.showWarning('제안할 수 있는 다른 업무가 없습니다.');
      return;
    }

    // [R5.3C.1] 개별 급여 제안은 canManageWage가 따로 필요하다 — 서버도 같다.
    //   권한이 없어도 옵션을 숨기지 않고 비활성 + 이유를 보여준다.
    final canManageWage = _permissionFor((p) => p.canManageWage);
    final picked = await AlternativeWorkOfferSheet.pickOffer(
      context,
      workerName: workerName,
      currentWork: currentWork,
      candidates: candidates,
      confirmedCountOf: _confirmedCountForWork,
      sourceWage: app.wage,
      sourceWageType: app.wageType,
      canManageWage: canManageWage,
    );
    if (picked == null || !mounted) return;
    final target = candidates.firstWhere((w) => w.id == picked.wdId);

    // [R7-P1-CORR] 시트 await 뒤 재확인 — 체크 시점의 false는 이미 낡았다.
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final sent = await AlternativeWorkOfferSheet.confirmAndSend(
        context,
        workerName: workerName,
        sourceApplicationId: app.id,
        target: target,
        option: picked.option,
        sourceWage: app.wage,
      );
      if (!sent || !mounted) return;
      await _loadApplicants();
      if (!mounted) return;
      await _updateLocalStats();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 개별 승인
  Future<void> _approveApplication(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    // [HIGH-02] 지원서 승인은 canManageTo 권한 필요
    if (!_canManageTo()) {
      ToastHelper.showWarning('지원서 처리 권한이 없습니다.');
      return;
    }
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final userProvider = context.read<UserProvider>();

    // 인원 체크 (일괄 승인과 동일 기준)
    final effectiveWork = _getWorkForApp(app) ?? widget.work;
    final blockReason = _capacityBlockReason(effectiveWork, 1);
    if (blockReason != null) {
      ToastHelper.showWarning(blockReason);
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final confirm = await DialogHelper.showConfirm(
        context,
        title: '지원 확정',
        message: '${_personLabelOf(user, '지원자')}님을 확정하시겠습니까?\n'
            '확정하면 바로 계약서 작성으로 이어지고, 근무자가 동의해야 출근할 수 있어요.',
        confirmText: '확정',
      );

      if (confirm != true || !mounted) return;

      final adminUID = userProvider.currentUser?.uid;

      final affectedTOIds = await _firestoreService.updateApplicationStatus(
        applicationId: app.id,
        // [CROSS-DOMAIN-R5.1D] 서버가 문서를 읽기 전에 인가하도록 사업장을 함께 보낸다
        businessId: app.businessId,
        status: AppStatus.confirmed,
        confirmedBy: adminUID,
      );

      // 🔥 충돌로 취소된 TO ID 수집
      if (affectedTOIds.isNotEmpty) {
        _affectedOtherTOIds.addAll(affectedTOIds);
        debugPrint('⚠️ 충돌로 ${affectedTOIds.length}개 TO 영향: $affectedTOIds');
      }

      if (!mounted) return;
      // [CONTRACT-DISPATCH-B3-HANDOFF] 계약 권한이 없으면 발송 대기와 인계처를 말한다.
      if (_canManageContract()) {
        ToastHelper.showSuccess('${_personLabelOf(user, '지원자')}님이 확정되었습니다. 계약서를 작성해 주세요.');
      } else {
        ToastHelper.showInfo("${_personLabelOf(user, '지원자')}님 확정 — 계약서 발송 대기예요. 계약 권한이 있는 관리자가 홈 '계약 미발송'에서 보낼 수 있어요.");
      }
      await _loadApplicants();
      if (!mounted) return;
      await _updateLocalStats();
      // [CONTRACT-BEFORE-CHECKIN] 확정 → 바로 계약서 발송(2026-10-25 사용자 지시). 기존 '계약서 작성'
      //   흐름(템플릿 → 사업주 날인 → 미리보기 → 서명)을 그대로 잇는다. 닫으면 발송되지 않은 채로 남고
      //   확정 행의 '계약서 작성' 버튼이 다음 일이다. 근무자는 동의해야 출근할 수 있다(서버 판정).
      if (!mounted) return;
      final fresh = _confirmed.where((i) => (i['application'] as ApplicationModel).id == app.id).firstOrNull;
      // 계약 권한이 없으면 잇지 않는다(행의 작성 버튼과 같은 조건 — worker_detail_dialog 와 대칭)
      if (fresh != null && _canManageContract() && _needsContractIssue(fresh['application'] as ApplicationModel)) {
        setState(() => _isProcessing = false);
        await _createContractForConfirmedUser(fresh);
      }
    } catch (e) {
      // [P4.4C.2A] 계약 준비가 깨져 확정이 막힌 경우는 이유를 준비 단계로
      //   잇는다. 여기는 원래 모든 실패를 한 문장으로 뭉갰다 — 관리자가
      //   무엇을 고쳐야 하는지 알 수 없었다.
      if (mounted) {
        if (PostingNotReady.parse(e) case final blocked?) {
          // [R7-PAYROLL-POLICY.4A §12] 이 이유만은 **그 지원자**에서 해결된다.
          //   이 화면은 사업장 문서를 들고 있지 않다 — 비교용 현재 기준 없이
          //   지원 당시 기준만 보여 준다. 읽기를 더하지 않는다(§31).
          if (blocked.reason ==
              PostingNotReadyReason.applicationPolicyNotAcknowledged) {
            final acked = await ApplicationPolicyAcknowledgeSheet.show(
              context,
              application: app,
              workerName: _personLabelOf(user, '지원자'),
            );
            if (acked && mounted) {
              setState(() => _isProcessing = false);
              await _approveApplication(item);
              return;
            }
            return;
          }
          final canSetUp = !context.read<UserProvider>().isSubAdmin;
          ToastHelper.showError(
              blocked.confirmBlockedNotice(canSetUp: canSetUp));
        } else {
          ToastHelper.showError('확정 처리 중 오류가 발생했습니다');
        }
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 개별 거절
  Future<void> _rejectApplication(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    // [HIGH-02] 지원서 거절은 canManageTo 권한 필요
    if (!_canManageTo()) {
      ToastHelper.showWarning('지원서 처리 권한이 없습니다.');
      return;
    }
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final userProvider = context.read<UserProvider>();

    setState(() => _isProcessing = true);
    try {
      final reason = await DialogHelper.showRejectReasonPicker(
        context,
        title: '지원 거절',
        message: '${_personLabelOf(user, '지원자')}님을 거절합니다.\n거절 사유를 선택해주세요.',
      );

      if (reason == null || !mounted) return;

      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.updateApplicationStatus(
        applicationId: app.id,
        status: AppStatus.rejected,
        rejectedBy: adminUID,
        message: reason,
      );

      if (!mounted) return;
      ToastHelper.showSuccess('${_personLabelOf(user, '지원자')}님이 거절되었습니다');
      await _loadApplicants();
      if (!mounted) return;
      await _updateLocalStats();
    } catch (e) {
      if (mounted) ToastHelper.showError('거절 처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// [BUG-CANCEL-01] 확정취소 가능 여부
  /// 단기 근무자 전용 — 장기는 이미 UI에서 '고정근무 관리' 버튼으로 분기됨
  bool _canCancelConfirmation(ApplicationModel app) {
    return _hasWorkedMap[app.uid] != true;
  }

  // ── [CROSS-DOMAIN-R5.3E.2] 확정 근무 변경 제안 ────────────────────────────

  /// 이 확정자에게 변경을 제안할 수 있는가 — 서버 조건의 화면 사본이다.
  ///
  /// 서버가 다시 전부 판정한다(계약·근태·정원·마감). 여기서는 눌러도 반드시
  /// 거절될 것만 미리 감춘다: 이미 근무했거나, 옮길 업무 자체가 없을 때.
  bool _canProposeReassignment(ApplicationModel app) {
    if (app.status != 'CONFIRMED') return false;
    if (_hasWorkedMap[app.uid] == true) return false;
    return _offerableWorkDetails(app).isNotEmpty;
  }

  ConfirmedReassignmentProposal? _pendingReassignmentOf(ApplicationModel app) {
    for (final p in _reassignProposals) {
      if (p.sourceApplicationId == app.id && p.isActionable) return p;
    }
    return null;
  }

  Future<void> _loadReassignProposals() async {
    final bizId = widget.toItem.to.businessId;
    if (bizId.isEmpty) return;
    try {
      final list = await _reads.reassignProposals(bizId);
      if (!mounted) return;
      setState(() => _reassignProposals = list);
    } catch (e) {
      // 읽기 실패를 "제안 없음"으로 바꾸지 않는다 — 이전 목록을 유지한다.
      debugPrint('[R5.3E.2] 변경 제안 목록 조회 실패: $e');
    }
  }

  /// [R7-P1-CORR] 근무 변경 제안도 제안 문서 + 알림을 만든다. 여기는 await가
  ///   둘(시트 + 확인)이라 중복 진입 창이 더 넓었다.
  Future<void> _showConfirmedReassignmentSheet(Map<String, dynamic> item) {
    final app = item['application'] as ApplicationModel;
    return ActionGuard.runVoid(
      ActionGuard.keyOf('confirmedReassign', [app.id]),
      () => _showConfirmedReassignmentSheetInner(item),
    );
  }

  Future<void> _showConfirmedReassignmentSheetInner(
      Map<String, dynamic> item) async {
    if (_isProcessing) return;
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final workerName = _personLabelOf(user, '근로자');
    final candidates = _offerableWorkDetails(app);
    if (candidates.isEmpty) {
      ToastHelper.showWarning('변경할 수 있는 다른 업무가 없습니다.');
      return;
    }
    final picked = await AlternativeWorkOfferSheet.pickOffer(
      context,
      workerName: workerName,
      currentWork: _getWorkForApp(app),
      candidates: candidates,
      confirmedCountOf: _confirmedCountForWork,
      sourceWage: app.wage,
      sourceWageType: app.wageType,
      canManageWage: _permissionFor((p) => p.canManageWage),
      sourceIsConfirmed: true,
    );
    if (picked == null || !mounted) return;
    final target = candidates.firstWhere((w) => w.id == picked.wdId);

    final ok = await DialogHelper.showConfirm(
      context,
      title: '근무 변경 제안',
      message: '$workerName님에게 ‘${target.workType}’ 업무로 변경을 제안합니다.\n'
          '${target.startTime}~${target.endTime}\n\n'
          '제안을 보내도 지금 확정된 근무는 그대로 유지됩니다. '
          '근로자가 수락한 순간에만 변경이 반영되고, '
          '기존 조건을 유지하면 아무것도 바뀌지 않습니다.',
      confirmText: '제안 보내기',
      cancelText: '취소',
    );
    if (ok != true || !mounted) return;

    // [R7-P1-CORR] 두 번의 await를 지나온 값이다 — 여기서 다시 확인한다.
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final pid = await ConfirmedReassignmentService.instance.propose(
        sourceApplicationId: app.id,
        targetWdId: target.id,
        compensationOption: picked.option,
      );
      if (pid == null || !mounted) return;
      ToastHelper.showSuccess('변경 제안을 보냈습니다. 근로자 확인을 기다립니다.');
      await _loadReassignProposals();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _cancelReassignment(ApplicationModel app) async {
    final p = _pendingReassignmentOf(app);
    if (p == null || _isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final done = await ConfirmedReassignmentSheet.confirmCancel(context, p);
      if (!done || !mounted) return;
      ToastHelper.showSuccess('변경 제안을 철회했습니다.');
      await _loadReassignProposals();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 확정취소 (단기)
  Future<void> _cancelConfirmation(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    // [HIGH-02] 확정 취소는 canManageTo 권한 필요
    if (!_canManageTo()) {
      ToastHelper.showWarning('확정 취소 권한이 없습니다.');
      return;
    }
    setState(() => _isProcessing = true);  // 사유 선택 다이얼로그 중 재진입 방지
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    final userProvider = context.read<UserProvider>();

    // [CONFIRM-CANCEL-COPY] 지원 거절 창이 아니라 확정 취소 전용 창(사유·버튼·기본 문구).
    final reason = await DialogHelper.showConfirmCancelReasonPicker(
      context,
      message: '${_personLabelOf(user, '근무자')}님의 확정된 근무를 취소합니다.\n취소 사유를 선택해 주세요.',
    );

    // [역전패턴 수정] 원래 "if (reason == null || !mounted)"였으나 !mounted 시에도 setState 호출되는 버그.
    // reason==null(사용자 취소)이면 로딩 해제 후 리턴, unmount면 setState 생략하고 리턴.
    if (reason == null) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    if (!mounted) return;
    try {
      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.cancelConfirmedApplication(
        app.id,
        canceledBy: adminUID,
        cancelReason: reason,
      );

      if (!mounted) return;
      ToastHelper.showSuccess('${_personLabelOf(user, '근무자')}님의 확정이 취소되었습니다');
      await _loadApplicants();
      if (!mounted) return;
      await _updateLocalStats();
    } catch (e) {
      if (mounted) ToastHelper.showError('확정 취소 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 고정근무 관리 다이얼로그 열기 (장기)
  // [B-3] item 파라미터 추가 → 해당 근무자 uid 전달로 자동 포커스
  void _openFixedWorkerManagement(Map<String, dynamic> item) {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final app = item['application'] as ApplicationModel;
    final businessId = widget.toItem.to.businessId;
    final onChanged = widget.onChanged;
    // 루트 Navigator는 이 다이얼로그가 pop된 후에도 유효
    final rootNav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop(_dialogResult);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: rootNav.context,
        barrierDismissible: false,
        builder: (_) => FixedWorkerManagementDialog(
          businessIds: [businessId],
          initialBusinessId: businessId,
          onChanged: onChanged,
          initialWorkerUid: app.uid,
        ),
      );
    });
  }

  /// 지원자 상세 보기 - 공통 위젯 사용
  Future<void> _showApplicantDetail(Map<String, dynamic> item) async{
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    
    if (user == null) {
      ToastHelper.showError('사용자 정보를 불러올 수 없습니다');
      return;
    }

    final isPending = app.status == AppStatus.pending;
    final isConfirmed = app.status == AppStatus.confirmed ||
        app.status == AppStatus.contractPending;

    final changed = await WorkerDetailDialog.show(
      context: context,
      user: user,
      application: app,
      toItem: widget.toItem,
      businessId: widget.toItem.to.businessId,
      isConfirmed: isConfirmed,
      showApprovalButtons: isPending,
      onStatusChanged: () async {
        await _loadApplicants();
        if (!mounted) return;
        _updateLocalStats();
      },
    );
    

    
    // 신분증 상태만 업데이트 (전체 새로고침 X)
    if (changed == true && mounted) {
      final userProvider = context.read<UserProvider>();
      final currentUserId = userProvider.currentUser?.uid ?? '';
      
      final newStatus = await IdCardHelper.loadStatusBatch(
        firestoreService: _firestoreService,
        requesterId: currentUserId,
        targetUserIds: [user.uid],
      );
      
      if (mounted) {
        setState(() {
          _idCardStatusMap.addAll(newStatus);
        });
      }
    }
  }

  /// 하단 액션 바
  Widget _buildBottomBar(BuildContext context) {
    if (!_isBatchMode) {
      return AppModalFooter(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context, _dialogResult),
              child: Text('닫기', style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
            ),
          ],
        ),
      );
    }

    final hasSelection = _selectedIds.isNotEmpty;
    // [CSA-02/E] batch approve = 승인+계약 통합 action → canManageContract 필요
    // 거절은 canManageTo만으로 충분 (계약 생성 없음).
    final canApproveWithContract = _canManageContract();
    return AppModalFooter(
      // [DU528] 한 줄에 다 들어가면 이전과 같은 자리(글 왼쪽 · 버튼 오른쪽 끝 · 세로 가운데), 안 들어가면 버튼 묶음을 아래 줄로(오른쪽 맞춤).
      child: SizedBox(width: double.infinity, child: OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        overflowAlignment: OverflowBarAlignment.end,
        overflowSpacing: ResponsiveHelper.spacing(context, 6),
        children: [
          Text(
            // [BULK-DISPATCH] 선택 단위는 지원서(=근무일)다. 슬롯 없이 들어오면
            //   같은 근로자의 다른 날짜가 여러 건으로 잡힌다 — "명"이 아니다.
            '선택: ${_selectedIds.length}건',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
          _buildBottomBarButton(
            context,
            label: '거절',
            icon: Icons.close,
            // [DU527a] 위험 행동은 면 없는 글자(행 버튼 '거절'과 같은 errorDark) — 확인 창은 그대로.
            bgColor: Colors.transparent,
            textColor: hasSelection ? AppColors.errorDark : AppColors.grey400,
            onTap: hasSelection ? () => _batchReject() : null,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          // [CSA-02/F] 계약 권한 없으면 승인 버튼 비활성(회색) — canManageTo만 있는 사용자에게
          // 실행 불가 action을 클릭 가능한 상태로 노출하지 않는다.
          _buildBottomBarButton(
            context,
            label: '확정',
            icon: Icons.check,
            // [DU527a] 주요 행동 하나만 brand 채움(행 버튼 '확정'과 같다).
            bgColor: (hasSelection && canApproveWithContract) ? AppColors.brand : AppColors.grey100,
            textColor: (hasSelection && canApproveWithContract) ? Colors.white : AppColors.grey400,
            onTap: (hasSelection && canApproveWithContract) ? () => _batchApprove() : null,
          ),
          ]),
        ],
      )),
    );
  }

  Widget _buildBottomBarButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 18),
            vertical: 14, // [DU527a] 받는 자리 세로 ≥48(본문 글자 약 24 + 28). 가로 · 글자 크기는 그대로.
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: ResponsiveHelper.iconSize(context, 15), color: textColor),
              SizedBox(width: ResponsiveHelper.spacing(context, 5)),
              Text(
                label,
                style: ResponsiveHelper.bodyStyle(context, color: textColor)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 일괄 승인 (계약서 생성 + 인감 날인 + 근무자 발송)
  Future<void> _batchApprove() async {
    if (_selectedIds.isEmpty || _isProcessing) return;
    // [HIGH-02] 일괄 승인은 canManageTo 권한 필요
    if (!_canManageTo()) {
      ToastHelper.showWarning('지원서 처리 권한이 없습니다.');
      return;
    }
    // [CSA-03] batch approve = 승인+계약 통합 → canManageContract도 필요.
    // mutation(CONFIRMED 변경) 전에 차단하여 CONFIRMED→PENDING 롤백 사이클 방지.
    if (!_canManageContract()) {
      ToastHelper.showWarning('계약서 관리 권한이 없습니다.');
      return;
    }

    // 인원 체크 (일괄 승인은 단일 업무 모드에서만 실행됨)
    // [R7-4 C6] 단건 승인과 같은 관문을 쓴다.
    final bulkBlockReason =
        _capacityBlockReason(widget.work, _selectedIds.length);
    if (bulkBlockReason != null) {
      ToastHelper.showWarning(bulkBlockReason);
      return;
    }

    // 첫 번째 await 전에 가드 설정 — 템플릿 선택 다이얼로그가 열려 있는 동안 중복 탭 차단
    setState(() => _isProcessing = true);

    // 1. 계약서 템플릿 선택
    final businessId = widget.toItem.to.businessId;
    final articles = await ContractTemplateSelectorDialog.show(context, businessId: businessId);
    if (articles == null) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    if (!mounted) return;

    // 2. 사업장 정보 + 인감 로드
    // [CSA-01] seal은 _resolveEmployerSeal()로 조회 — SUB_ADMIN은 owner seal 사용
    late BusinessModel business;
    const String? sealBase64 = null;
    const String sealType = 'stamp';
    bool continueToProcess = false;

    try {
      final b = await _firestoreService.getBusinessById(businessId);
      if (b == null) {
        if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
        return;
      }
      business = b;
      final sealReady = await _employerSealReady(business);
      if (sealReady != true) {
        if (!mounted) return;
        if (sealReady == null) {
          ToastHelper.showError('사업주 날인 상태를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
        } else {
          await _showSealMissingDialog(isBatchApprove: true);
        }
        return;
      }
      continueToProcess = true;
    } catch (e) {
      debugPrint('❌ [_batchApprove] 사업장 정보 조회 실패: $e');
      if (mounted) ToastHelper.showError('사업장 정보를 불러오는 중 오류가 발생했습니다');
    } finally {
      // 실제 일괄 처리로 이어지는 경우 _isProcessing을 유지, 아니면 복원
      if (!continueToProcess && mounted) setState(() => _isProcessing = false);
    }

    if (!mounted) return;

    // 3. 처리 대상 확정 → 그중 첫 건으로 미리보기 계약서 생성
    //
    //   [BULK-DISPATCH] 대상 수집을 미리보기 **앞**으로 옮겼다. 두 가지 때문이다.
    //     · 미리보기가 약속하는 건수와 실제로 시도하는 건수가 같아진다.
    //       (전에는 `_selectedIds.length` 를 보여 주고, 지원자 정보를 못 읽은
    //        건은 조용히 빠진 채 "일부 실패"로 끝났다)
    //     · 첫 선택 건의 지원자 정보가 없으면 **나머지 멀쩡한 선택까지**
    //       전부 중단됐다. 이제 시도 가능한 것 중 첫 건을 쓴다.
    final toProcess = <Map<String, dynamic>>[];
    for (final appId in _selectedIds.toList()) {
      final item = _applicants.firstWhere(
        (i) => (i['application'] as ApplicationModel).id == appId,
        orElse: () => <String, dynamic>{},
      );
      if (item.isNotEmpty && item['user'] != null) toProcess.add(item);
    }
    final skippedCount = _selectedIds.length - toProcess.length;
    if (toProcess.isEmpty) {
      ToastHelper.showWarning('선택한 $skippedCount건의 지원자 정보를 불러오지 못했습니다. '
          '목록을 새로고침한 뒤 다시 시도해주세요.');
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    final firstItem = toProcess.first;
    final firstApp = firstItem['application'] as ApplicationModel;
    final firstUser = firstItem['user'] as UserModel;
    final firstWorkDetail = widget.work ?? _getWorkForApp(firstApp);
    if (firstWorkDetail == null) {
      ToastHelper.showError('업무 정보를 찾을 수 없습니다');
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    setState(() => _isProcessing = true);
    late EmploymentContractModel previewContract;
    try {
      // buildPreviewContract: 번들 탐색 없이 항상 isNewUnsaved=true 반환 → Firestore 미저장
      previewContract = await ContractService().buildPreviewContract(
        application: firstApp,
        business: business,
        worker: firstUser,
        workDetail: firstWorkDetail,
        articles: articles,
      );
    } catch (e) {
      if (mounted) ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
      return;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }

    if (!mounted) return;

    // 4. 미리보기 다이얼로그
    final confirmed = await _showBatchContractPreview(
      contract: previewContract,
      sealBase64: sealBase64,
      sealType: sealType,
      count: toProcess.length,
    );
    if (confirmed != true || !mounted) return;

    // 5. 일괄 처리
    setState(() => _isProcessing = true);
    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid;
  
      // 처리 대상(`toProcess`)·시도 못 한 수(`skippedCount`)는 미리보기 전에
      //   이미 확정했다 — 관리자가 승인한 건수와 같은 집합으로 돌린다.

      // [BULK-DISPATCH-RECONCILE] 실패로 **보이는** 결과를 원장에 물어 확정한다.
      //
      //   불변식: **계약이 있거나 있는지 확인할 수 없으면 되돌리지 않는다.**
      //
      //   오류 코드는 어디까지 처리됐는지 말해 주지 않는다. 서버는 트랜잭션
      //   커밋 뒤로는 던지지 않지만(알림 실패는 CF 안에서 삼킨다), 전송 계층과
      //   클라이언트 파싱은 **커밋 뒤에도** 던질 수 있다. 그래서 코드로 추측하지
      //   않고 그 지원서 하나의 원장을 본다.
      //
      // ─────────────────────────────────────────────────────────────────
      // [ROLLBACK-ATOMICITY] **확정 롤백은 더 이상 하지 않는다.**
      //
      //   원장을 읽고 쓰기까지의 틈에 다른 관리자가 계약을 발행할 수 있다.
      //   그러면 예전 코드는 그 **정상 계약을 void 하고** 지원서를 PENDING 으로
      //   되돌렸다(실측 재현: scripts/rbatom-rollback-race.js RA-A/M1).
      //
      //   그 틈을 닫을 수 있는지 세 모델로 실측했다.
      //     · 지원서 문서만 트랜잭션 → 계약은 **다른 컬렉션의 새 문서**라
      //       충돌로 잡히지 않는다. 게다가 클라이언트 SDK 트랜잭션은
      //       쿼리를 읽을 수 없어 "계약이 없다"를 트랜잭션 안에서 물을 수도 없다.
      //     · 서버 트랜잭션 안에서 원장을 질의 → 읽을 때 **없던** 문서는
      //       phantom 이라 잡히지 않는다.
      //     · 발행과 롤백이 지원서 표식을 공유 → 가능해 보이지만, 그 안전성은
      //       프로덕션 Firestore 트랜잭션 의미론에 달려 있고 격리 에뮬레이터는
      //       충돌 감지 자체를 하지 않아(RA-X0) **입증할 수 없다.**
      //
      //   입증되지 않은 안전성에 기대어 남의 계약을 void 할 수는 없다. 쓰기를
      //   하지 않으면 그 위험은 **의미론과 무관하게 0** 이다. 그래서 좌석을
      //   유지하고 관리자에게 재발송을 요구한다(`needsReissue`).
      //   확정이 남으니 겹침 자동취소(B)도 올바른 결과가 되어, 예전
      //   `batchRollbackWithCollateral` 경고가 가리켰던 **복구 불가 2차 피해가
      //   애초에 생기지 않는다.**
      //
      //   되살리는 조건: 계약 발행 CF 가 **같은 트랜잭션에서** 지원서에 표식을
      //   쓰고(설계는 하네스 M4), 그 경쟁이 실제 Firestore 에서 입증될 때.
      // ─────────────────────────────────────────────────────────────────
      //
      //   남은 판단은 **쓰기 없는 분류**다.
      //     ① 원장 조회가 성공했고, 발송된 계약이 없다
      //     ② 지원서를 다시 읽을 수 있다
      //     ③ 이미 PENDING → 확정 전 실패(확인된 실패)
      //     ④ 좌석 보유 상태 그대로 → `needsReissue`
      //     ⑤ 그 밖(취소·노쇼·끝난 관계) → `rejected`
      //   하나라도 확인되지 않으면 `unknown` 으로 남긴다.
      //
      //   `mayRollback: false` 는 **응답을 못 받은** 경우다. 그때 원장이
      //   "없다"고 답해도 좌석 판단으로 넘어가지 않는다 — 그 요청이 아직
      //   서버에서 살아 있을 수 있어서, 읽은 직후에 커밋될 수 있다.
      //   그 경우 원장 조회는 `already` 로 **올려 주는 데만** 쓴다.
      Future<String> settleFailure(String appId, Object err,
          {required bool mayRollback}) async {
        final probe = await ContractService()
            .probeIssuedContract(appId, businessId: businessId);
        if (probe == ContractLedgerProbe.issued) {
          debugPrint('ℹ️ [$appId] 실패로 보였지만 계약이 원장에 있다 — 롤백 금지: $err');
          return 'already';
        }
        if (probe == ContractLedgerProbe.unknown) {
          debugPrint('⚠️ [$appId] 원장 확인 불가 — 롤백 금지: $err');
          return 'unknown';
        }
        if (!mayRollback) {
          debugPrint('⚠️ [$appId] 응답 미수신 — 원장에 없지만 진행 중일 수 있어 롤백 금지');
          return 'unknown';
        }

        // ② 지원서 재조회 — 읽기 실패를 "되돌려도 된다"로 바꾸지 않는다.
        final DocumentSnapshot<Map<String, dynamic>> appSnap;
        try {
          appSnap = await FirebaseFirestore.instance
              .collection('applications')
              .doc(appId)
              .get(const GetOptions(source: Source.server));
        } catch (readErr) {
          debugPrint('⚠️ [$appId] 지원서 재조회 실패 — 롤백 금지: $readErr');
          return 'unknown';
        }
        if (!appSnap.exists) {
          debugPrint('⚠️ [$appId] 지원서가 없다 — 되돌릴 대상이 없다: $err');
          return 'unknown';
        }
        final appData = appSnap.data() ?? const <String, dynamic>{};

        // ③-0 이미 PENDING 이면 **되돌릴 것이 없다.**
        //   확정 자체가 실패한 경우가 여기다 — 쓸 필요도 없고, 이것은
        //   계약도 없고 좌석도 안 잡힌 **확인된 실패**다.
        if ((appData['status'] as String?) == AppStatus.pending) {
          debugPrint('❌ [$appId] 확정 전 실패 — 되돌릴 것이 없다: $err');
          return 'failed';
        }

        // ⑤ 다른 요청·사람이 뒤이어 바꿨는가.
        //
        //   확정은 `callableConfirmApplication` 이 하고, 그 CF 가 쓰는 값은
        //   **`CONTRACT_PENDING`** 이다(`CONFIRMED` 가 아니다 — 여기를
        //   `CONFIRMED` 로만 적으면 정상 경로가 전부 이 분기로 떨어진다).
        //   둘 다 "좌석 보유·계약 미발송"을 뜻하므로 서버의 좌석 집합
        //   (CONFIRMED_STATUSES)과 같은 한 벌을 쓴다.
        //   CANCELED·NO_SHOW·REJECTED·EXPIRED, 그리고 누군가 이미 PENDING 으로
        //   되돌린 경우는 모두 여기서 걸러진다.
        final nowStatus = appData['status'] as String?;
        if (nowStatus == null ||
            !AppStatus.confirmedStatuses.contains(nowStatus)) {
          debugPrint('⚠️ [$appId] 후속 변경 감지 (status=$nowStatus): $err');
          return 'rejected';
        }
        // 좌석 반납·해지·퇴사로 끝난 관계도 "건드리지 않는다"에 해당한다.
        //    CF 의 발송 대상 판정(srvNeedsContractIssue)과 같은 필드를 본다.
        const endedStatuses = {'APPROVED', 'AUTO_APPROVED'};
        if (appData['staffingReleasedAt'] != null ||
            endedStatuses.contains(appData['terminationStatus'] as String?) ||
            endedStatuses.contains(appData['resignStatus'] as String?)) {
          debugPrint('⚠️ [$appId] 끝난 관계 — 건드리지 않는다: $err');
          return 'rejected';
        }

        // ④ 좌석은 유효하고 계약만 없다. **쓰지 않는다.**
        //   확정을 그대로 두고 관리자에게 재발송을 요구한다.
        debugPrint('❌ [$appId] 확정 유지 + 계약 미발송 — 재발송 필요: $err');
        return 'needsReissue';
      }

      // 단건 처리 함수
      //   'sent' | 'already' | 'needsReissue' | 'rejected' | 'unknown' | 'failed'
      Future<String> processOne(Map<String, dynamic> item) async {
        final app = item['application'] as ApplicationModel;
        final user = item['user'] as UserModel;
        final appId = app.id;
        final appWorkDetail = widget.work ?? _getWorkForApp(app);
        if (appWorkDetail == null) return 'failed';
        try {
          final affectedTOIds = await _firestoreService.updateApplicationStatus(
            applicationId: appId,
            // [CONFIRM-BUSINESSID] 확정 CF 는 businessId 가 없으면 invalid-argument 로
            //   거절한다 — 이 일괄 경로는 그래서 한 건도 확정하지 못했다.
            //   지원서 자신의 사업장을 보낸다(같은 창의 개별 확정과 같은 값).
            businessId: app.businessId,
            status: AppStatus.confirmed,
            confirmedBy: adminUID,
          );
          if (affectedTOIds.isNotEmpty) {
            // 확정 시 겹치는 B 지원서가 AUTO_CANCELED 된다.
            // [ROLLBACK-ATOMICITY] 예전에는 이 사실을 "롤백 시 B 는 복구
            //   불가"라는 경고로 이어 붙였다. 이제 확정을 되돌리지 않으므로
            //   B 의 자동취소는 **옳은 결과**다 — 경고할 일이 아니다.
            _affectedOtherTOIds.addAll(affectedTOIds);
          }
          // [BUG-수정 M-1] updateApplicationStatus 완료 후 Firestore에는 computedWorkEndDate가
          // 저장되지만 로컬 app 객체는 구버전이라 workEndDate가 null일 수 있음.
          // 서버에서 최신 데이터를 재조회해 contractEnd 공백 발급 버그를 방지.
          final freshAppDoc = await FirebaseFirestore.instance
              .collection('applications')
              .doc(appId)
              .get(const GetOptions(source: Source.server));
          // 승인 처리 직후 문서가 삭제된 경쟁 상태 방어 (catch(itemErr)로 롤백됨)
          if (!freshAppDoc.exists) throw Exception('지원서를 찾을 수 없습니다');
          // [BUG-H1-P2 수정 2026-07-15] fromMap → tryFromFirestore: 파싱 실패 시 크래시 대신 명시적 예외
          final freshApp = ApplicationModel.tryFromFirestore(freshAppDoc) ??
              (throw Exception('승인 후 지원서 파싱 실패'));
          final contract = await ContractService().findOrCreateContract(
            application: freshApp,
            business: business,
            worker: user,
            workDetail: appWorkDetail,
            articles: articles,
          );
          await ContractService().saveEmployerSignature(
            contract: contract,
          );
          return 'sent';
        } on FirebaseFunctionsException catch (e) {
          // [BULK-DISPATCH] "이미 발송된 근무"는 **실패가 아니다.**
          //
          //   예전에는 이것도 아래 catch 로 떨어져 확정을 PENDING 으로
          //   되돌렸다. 계약서는 서버에 멀쩡히 살아 있는데 지원서만 PENDING 이
          //   되어 **계약과 지원서 상태가 어긋난다.** 관리자에게도 "실패"로
          //   보여 다시 누르게 만들고, 눌러도 또 같은 결과다.
          //   day_applicants_dialog 는 이미 이렇게 구별하고 있었다.
          if (e.code == 'already-exists') {
            debugPrint('ℹ️ [$appId] 이미 발송된 근무 — 중복 발송 차단됨');
            return 'already';
          }
          // [BULK-DISPATCH] 응답을 못 받은 것은 **실패가 아니다.**
          //
          //   타임아웃·연결 끊김에서는 서버가 계약서를 이미 썼는지 알 수 없다.
          //   여기서 PENDING 으로 되돌리면, 커밋됐을 때 근로자는 **지원서가
          //   PENDING 인 계약서에 서명하게 된다.** 확정 상태를 그대로 두는 쪽이
          //   복구 가능하다 — 계약서가 없으면 `계약 미작성 확정자`로 보이고
          //   관리자가 다시 보내면 되고, 있으면 그대로 맞는 상태다.
          if (_indeterminateCfCodes.contains(e.code)) {
            debugPrint('⚠️ [$appId] 처리 여부 확인 불가 (${e.code})');
            // [BULK-DISPATCH-RECONCILE] 원장을 한 번 본다. 단 **올려 주는 데만**
            //   쓴다 — 계약이 보이면 `already`, 아니면 그대로 `unknown`.
            //   되돌리지는 않는다(요청이 아직 진행 중일 수 있다).
            return settleFailure(appId, e, mayRollback: false);
          }
          // [BULK-DISPATCH-RECONCILE] 오류 코드 하나로 결과를 정하지 않는다.
          //   원장에 물어본 뒤 분류한다 — 위 settleFailure.
          return settleFailure(appId, e, mayRollback: true);
        } catch (itemErr) {
          // [BULK-DISPATCH-RECONCILE] **커밋 뒤에 터지는 예외도 여기로 온다.**
          //   예: CF 응답을 다 받고 나서 `saveEmployerSignature` 가 응답 모양을
          //   검사하다 던지는 경우. 계약은 이미 저장됐는데 예외 하나만 보고
          //   되돌리면 지원서와 계약이 어긋난다. 그래서 원장을 본다.
          return settleFailure(appId, itemErr, mayRollback: true);
        }
      }

      // 5개씩 배치 병렬 처리 (Firebase rate limit 고려)
      const batchSize = 5;
      int successCount = 0;
      int alreadyCount = 0;
      int unknownCount = 0;
      int reissueCount = 0;
      int rejectedCount = 0;
      for (var i = 0; i < toProcess.length; i += batchSize) {
        final batch = toProcess.sublist(i, min(i + batchSize, toProcess.length));
        final results = await Future.wait(batch.map(processOne));
        successCount += results.where((r) => r == 'sent').length;
        alreadyCount += results.where((r) => r == 'already').length;
        unknownCount += results.where((r) => r == 'unknown').length;
        reissueCount += results.where((r) => r == 'needsReissue').length;
        rejectedCount += results.where((r) => r == 'rejected').length;
      }
      if (!mounted) return;

      // [BULK-DISPATCH] 단위는 **건**이다 — 선택은 지원서 단위라서 같은
      //   근로자의 다른 날짜가 여러 건으로 잡힌다. "명"으로 적으면 사람 수로
      //   읽힌다(같은 사람의 3일이 "3명"이 됐다).
      //   기준도 `toProcess.length` 로 맞춘다 — `_selectedIds` 에는 사용자
      //   정보를 못 읽어 처리에서 빠진 것도 들어 있어 항상 실패처럼 보였다.
      final failedCount = toProcess.length -
          successCount - alreadyCount - unknownCount -
          reissueCount - rejectedCount;
      // [ROLLBACK-ATOMICITY] 네 가지를 서로 다른 문장으로 말한다.
      //   섞으면 관리자가 할 일을 못 고른다 — 재발송할 건, 확인할 건,
      //   손대지 않은 건, 시도조차 못 한 건은 각자 다른 행동을 부른다.
      final skippedMsg = skippedCount > 0
          ? '\n$skippedCount건은 지원자 정보를 불러오지 못해 시도하지 못했습니다.'
          : '';
      final unknownMsg = unknownCount > 0
          ? '\n$unknownCount건은 처리 여부를 확인하지 못했습니다. 목록에서 계약 상태를 확인해주세요.'
          : '';
      final reissueMsg = reissueCount > 0
          ? '\n$reissueCount건은 확정은 유지됐고 계약서만 발송되지 않았습니다. '
              '계약서 미작성 목록에서 다시 발송해주세요.'
          : '';
      final rejectedMsg = rejectedCount > 0
          ? '\n$rejectedCount건은 그 사이 다른 변경이 있어 건드리지 않았습니다.'
          : '';
      final tailMsg = '$reissueMsg$rejectedMsg$unknownMsg$skippedMsg';
      if (failedCount > 0) {
        ToastHelper.showWarning(
            '$successCount/${toProcess.length}건 계약서 발송 완료. '
            '실패한 $failedCount건은 다시 시도해주세요.$tailMsg');
      } else if (tailMsg.isNotEmpty) {
        // 시도한 것은 전부 됐더라도 **전부는 아니다** — 성공으로 끝내지 않는다.
        ToastHelper.showWarning('$successCount건 계약서 발송 완료.'
            '${alreadyCount > 0 ? ' ($alreadyCount건은 이미 발송된 근무)' : ''}'
            '$tailMsg');
      } else if (alreadyCount > 0) {
        ToastHelper.showSuccess(successCount > 0
            ? '$successCount건 계약서를 발송했습니다 ($alreadyCount건은 이미 발송된 근무)'
            : '$alreadyCount건은 이미 계약서가 발송된 근무예요');
      } else {
        ToastHelper.showSuccess('${toProcess.length}건 계약서를 발송했습니다');
      }
      _selectedIds.clear();
      if (mounted) setState(() { _isBatchMode = false; _selectAll = false; });
      await _loadApplicants();
      await _updateLocalStats();
      if (!mounted) return;

      for (var toId in _affectedOtherTOIds) {
        _firestoreService.clearCache(toId: toId);
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했습니다');
      debugPrint('❌ 일괄 계약 발송 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 일괄 계약서 미리보기 다이얼로그
  Future<bool?> _showBatchContractPreview({
    required EmploymentContractModel contract,
    required String? sealBase64,
    String sealType = 'stamp',
    required int count,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                color: Theme.of(ctx).primaryColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '근로계약서 미리보기',
                      style: ResponsiveHelper.subtitleStyle(ctx).copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            // 안내 배너
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.grey100,
              child: Text(
                // [BULK-DISPATCH] 한 근무일 = 한 계약 = 한 장이다.
                //   "N명에게"는 사람 수로 읽혀서, 같은 사람의 3일을 고른
                //   관리자가 3명에게 보내는 줄 알았다.
                '아래 조건으로 선택한 $count건의 근무에 계약서가 발송됩니다.\n'
                '근무일마다 계약서가 1장씩 따로 만들어집니다.\n'
                '이름·생년월일 등 개인정보는 각 근무자별로 적용됩니다.',
                style: ResponsiveHelper.smallStyle(ctx, color: AppColors.textPrimary),
                textAlign: TextAlign.center,
              ),
            ),
            // 계약서 본문
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ContractTemplateWidget(
                  snapshot: contract.snapshot,
                  contractDate: contract.createdAt,
                  slots: contract.slots,
                  articles: contract.articles,
                  // [R8P6-SIG-CUTOVER] 서명 이미지는 열 때마다 서버가 권한을
                  //   보고 15분 링크를 낸다 — 계약과 역할만 넘긴다.
                  contractId: contract.id,
                  hasEmployerSignature: contract.hasEmployerSignature,
                  hasWorkerSignature: contract.hasWorkerSignature,
                  employerSealBase64: sealBase64,
                  employerSealType: sealType,
                ),
              ),
            ),
            // 하단 버튼
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
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
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('$count건 발송'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 확정자 계약서 일괄작성 (이미 확정된 상태 → 상태 변경 없이 계약서만 생성)
  Future<void> _batchCreateContractsForConfirmed() async {
    if (_isContractBatchProcessing) return;
    setState(() => _isContractBatchProcessing = true);
    final businessId = widget.toItem.to.businessId;

    // 1. 템플릿 선택
    final articles = await ContractTemplateSelectorDialog.show(context, businessId: businessId);
    if (articles == null || !mounted) {
      if (mounted) setState(() => _isContractBatchProcessing = false);
      return;
    }

    // 2. 사업장 정보 로드 + 인감 확인
    // [CSA-01] seal은 _resolveEmployerSeal()로 조회 — SUB_ADMIN은 owner seal 사용
    late BusinessModel business;
    const String? sealBase64 = null;
    const String sealType = 'stamp';
    try {
      final b = await _firestoreService.getBusinessById(businessId);
      if (b == null) {
        if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
        return;
      }
      business = b;
      final sealReady = await _employerSealReady(business);
      if (sealReady != true) {
        if (!mounted) return;
        if (sealReady == null) {
          ToastHelper.showError('사업주 날인 상태를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
        } else {
          await _showSealMissingDialog(isBatchApprove: true);
        }
        setState(() => _isContractBatchProcessing = false);
        return;
      }
    } catch (e) {
      debugPrint('❌ [_batchCreateContractsForConfirmed] 사업장 정보 조회 실패: $e');
      if (mounted) ToastHelper.showError('사업장 정보를 불러오는 중 오류가 발생했습니다');
      return;
    } finally {
      if (mounted) setState(() => _isContractBatchProcessing = false);
    }
    if (!mounted) return;

    // 4. 계약 미작성 확정자 수집
    //   [REISSUE-RECOVERY] 판정은 한 곳(_needsContractIssue)만 쓴다 —
    //   조회 실패를 대상에 넣지 않고, 좌석을 반납한 건도 넣지 않는다.
    final toProcess = _applicants
        .where((item) =>
            _needsContractIssue(item['application'] as ApplicationModel))
        .toList();
    if (toProcess.isEmpty) return;

    // 5. 첫 번째 대상으로 미리보기 생성
    final firstApp = toProcess.first['application'] as ApplicationModel;
    final firstUser = toProcess.first['user'] as UserModel?;
    if (firstUser == null) {
      ToastHelper.showError('지원자 정보를 불러올 수 없습니다');
      return;
    }
    final firstWorkDetail = widget.work ?? _getWorkForApp(firstApp);
    if (firstWorkDetail == null) {
      ToastHelper.showError('업무 정보를 찾을 수 없습니다');
      return;
    }

    setState(() => _isContractBatchProcessing = true);
    late EmploymentContractModel previewContract;
    try {
      previewContract = await ContractService().buildPreviewContract(
        application: firstApp,
        business: business,
        worker: firstUser,
        workDetail: firstWorkDetail,
        articles: articles,
      );
    } catch (e) {
      if (mounted) ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
      return;
    } finally {
      if (mounted) setState(() => _isContractBatchProcessing = false);
    }
    if (!mounted) return;

    // 6. 미리보기 다이얼로그
    final confirmed = await _showBatchContractPreview(
      contract: previewContract,
      sealBase64: sealBase64,
      sealType: sealType,
      count: toProcess.length,
    );
    if (confirmed != true || !mounted) return;

    // 7. 일괄 계약서 생성 + 날인
    setState(() => _isContractBatchProcessing = true);
    try {
      // [BULK-DISPATCH] 'sent' | 'already' | 'failed' — 세 결과를 구별한다.
      //   `already-exists` 는 서버가 **중복 발송을 막은 것**이고 계약서는 이미
      //   있다. 실패로 적으면 관리자가 눌러도 눌러도 같은 경고를 본다.
      Future<String> processOne(Map<String, dynamic> item) async {
        final app = item['application'] as ApplicationModel;
        final user = item['user'] as UserModel?;
        if (user == null) return 'failed';
        final appWorkDetail = widget.work ?? _getWorkForApp(app);
        if (appWorkDetail == null) return 'failed';
        try {
          final contract = await ContractService().findOrCreateContract(
            application: app,
            business: business,
            worker: user,
            workDetail: appWorkDetail,
            articles: articles,
          );
          await ContractService().saveEmployerSignature(
            contract: contract,
          );
          return 'sent';
        } on FirebaseFunctionsException catch (e) {
          if (e.code == 'already-exists') {
            debugPrint('ℹ️ [${app.id}] 이미 발송된 근무 — 중복 발송 차단됨');
            return 'already';
          }
          debugPrint('❌ [${app.id}] 계약서 발송 실패: $e');
          return 'failed';
        } catch (e) {
          debugPrint('❌ [${app.id}] 계약서 발송 실패: $e');
          return 'failed';
        }
      }

      const batchSize = 5;
      int successCount = 0;
      int alreadyCount = 0;
      final List<Map<String, dynamic>> successItems = [];
      for (var i = 0; i < toProcess.length; i += batchSize) {
        final batch = toProcess.sublist(i, min(i + batchSize, toProcess.length));
        final results = await Future.wait(batch.map(processOne));
        if (!mounted) return;
        for (var j = 0; j < batch.length; j++) {
          if (results[j] == 'sent') {
            successCount++;
            successItems.add(batch[j]);
          } else if (results[j] == 'already') {
            alreadyCount++;
          }
        }
      }

      if (!mounted) return;
      // [BULK-DISPATCH] 단위는 **건**이다 — 한 근무일 = 한 독립 계약이라서
      //   같은 근로자의 3일이 3건으로 잡힌다. "명"으로 적으면 사람 수로 읽힌다.
      final failedCount = toProcess.length - successCount - alreadyCount;
      if (failedCount > 0) {
        ToastHelper.showWarning('$successCount/${toProcess.length}건 계약서 발송 완료. '
            '실패한 $failedCount건은 다시 시도해주세요.');
      } else if (alreadyCount > 0) {
        ToastHelper.showSuccess(successCount > 0
            ? '$successCount건 계약서를 발송했습니다 ($alreadyCount건은 이미 발송된 근무)'
            : '$alreadyCount건은 이미 계약서가 발송된 근무예요');
      } else {
        ToastHelper.showSuccess('${toProcess.length}건 계약서를 발송했습니다');
      }
      if (successCount > 0) {
        _hasChanges = true;
        setState(() {
          for (final item in successItems) {
            final app = item['application'] as ApplicationModel;
            _contractStatusMap = _contractStatusMap.withStatus(app.id, 'pending_worker');
          }
        });
      }
      // 이미 발송된 건은 **현재 상태를 모른다**(근로자가 서명했을 수도 있다).
      //   `pending_worker` 로 추측해 쓰지 않고 서버에서 다시 읽는다.
      if (alreadyCount > 0) {
        _hasChanges = true;
        await _loadApplicants();
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했습니다');
      debugPrint('❌ 계약서 일괄 발송 실패: $e');
    } finally {
      if (mounted) setState(() => _isContractBatchProcessing = false);
    }
  }

  /// 개별 계약서 작성 (확정자 단건)
  Future<void> _createContractForConfirmedUser(Map<String, dynamic> item) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;
    if (user == null) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    final businessId = widget.toItem.to.businessId;

    // 1. 템플릿 선택
    final articles = await ContractTemplateSelectorDialog.show(context, businessId: businessId);
    if (articles == null || !mounted) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    // 2. 사업장 정보 로드 + 인감 확인 + 미리보기 생성
    // [CSA-01] seal은 _resolveEmployerSeal()로 조회 — SUB_ADMIN은 owner seal 사용
    final resolvedWork = widget.work ?? _getWorkForApp(app);
    if (resolvedWork == null) {
      ToastHelper.showError('업무 정보를 찾을 수 없습니다');
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    const String? sealBase64 = null;
    const String sealType = 'stamp';
    late EmploymentContractModel previewContract;
    try {
      final b = await _firestoreService.getBusinessById(businessId);
      if (b == null) {
        if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
        return;
      }
      final sealReady = await _employerSealReady(b);
      if (sealReady != true) {
        if (!mounted) return;
        if (sealReady == null) {
          ToastHelper.showError('사업주 날인 상태를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
        } else {
          await _showSealMissingDialog(isBatchApprove: false);
        }
        setState(() => _isProcessing = false);
        return;
      }
      previewContract = await ContractService().buildPreviewContract(
        application: app,
        business: b,
        worker: user,
        workDetail: resolvedWork,
        articles: articles,
      );
    } catch (e) {
      if (mounted) ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
      return;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
    if (!mounted) return;

    // 4. 미리보기
    final ok = await _showBatchContractPreview(
      contract: previewContract,
      sealBase64: sealBase64,
      sealType: sealType,
      count: 1,
    );
    if (ok != true || !mounted) return;

    // 5. 계약서 생성 + 날인
    setState(() => _isProcessing = true);
    try {
      final b = await _firestoreService.getBusinessById(businessId);
      if (b == null) {
        if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
        return;
      }
        final contract = await ContractService().findOrCreateContract(
        application: app,
        business: b,
        worker: user,
        workDetail: resolvedWork,
        articles: articles,
      );
      await ContractService().saveEmployerSignature(
        contract: contract,
      );
      if (!mounted) return;
      ToastHelper.showSuccess('계약서가 발송되었습니다');
      _hasChanges = true;
      setState(() => _contractStatusMap = _contractStatusMap.withStatus(app.id, 'pending_worker'));
    } catch (e) {
      if (mounted) ToastHelper.showError('계약서 발송 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 일괄 거절
  Future<void> _batchReject() async {
    if (_selectedIds.isEmpty || _isProcessing) return;
    // [HIGH-02] 일괄 거절은 canManageTo 권한 필요
    if (!_canManageTo()) {
      ToastHelper.showWarning('지원서 처리 권한이 없습니다.');
      return;
    }
    setState(() => _isProcessing = true);

    final userProvider = context.read<UserProvider>();
    final reason = await DialogHelper.showRejectReasonPicker(
      context,
      title: '일괄 거절',
      // [BULK-DISPATCH] 같은 선택 집합이므로 단위도 같다 — 지원서(근무일) 건수다.
      message: '선택한 ${_selectedIds.length}건의 지원을 거절합니다.\n거절 사유를 선택해주세요.',
    );

    if (reason == null || !mounted) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    try {
      final adminUID = userProvider.currentUser?.uid;
      // 순회 중 컬렉션 변경을 방지하기 위해 복사본으로 순회
      final idsToReject = List<String>.from(_selectedIds);

      // 병렬 거절 처리 — 개별 try-catch로 성공/실패 카운팅
      final rejectResults = await Future.wait(idsToReject.map((appId) async {
        try {
          await _firestoreService.updateApplicationStatus(
            applicationId: appId,
            status: AppStatus.rejected,
            rejectedBy: adminUID,
            message: reason,
          );
          return true;
        } catch (e) {
          debugPrint('❌ [_batchReject] 거절 실패 [$appId]: $e');
          return false;
        }
      }));
      final successCount = rejectResults.where((r) => r).length;
      final failCount = rejectResults.where((r) => !r).length;

      if (!mounted) return;
      if (successCount > 0) {
        final msg = failCount > 0
            ? '$successCount건 거절 완료 ($failCount건 실패)'
            : '$successCount건의 지원을 거절했습니다';
        ToastHelper.showSuccess(msg);
        _selectedIds.clear();
        await _loadApplicants();
        if (!mounted) return;
        await _updateLocalStats();
      } else {
        ToastHelper.showError('거절 처리 중 오류가 발생했습니다');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('거절 처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
  /// 로컬 통계 갱신 (toItem의 workDetailStats + slot 단위 카운트 업데이트)
  /// _loadApplicants 직후 캐시된 _allApplications를 재사용해 이중 fetch 방지
  Future<void> _updateLocalStats({bool markChanged = true}) async {
    // 첫 로드에서는 변경이 아니다 — 부모에게 갱신을 요구하지 않는다.
    if (markChanged) _hasChanges = true;

    // [R7-P1-2 DEVICE.1E.1 §3] 로컬 재집계는 **과도기 값**이다.
    //
    //   `_allApplications` 는 `callableGetApplicationsByBiz` 의 결과이고
    //   그 callable 은 페이징한다(`hasMore`/`lastDocId`). 즉 이 목록은
    //   부분집합일 수 있다 — 부분집합으로 전체 자리 수를 주장할 수 없다.
    //   서버가 세는 좌석은 정원 가드·반납·자동취소까지 반영한다.
    //
    //   그래서 두 가지를 지킨다.
    //     mutation 직후 → 즉시 반응을 위해 로컬 값을 쓰고 **반드시**
    //                     canonical 재조회를 이어 붙인다.
    //     최초 로드     → 로컬 값을 정원으로 쓰지 않는다. initState 가
    //                     이미 canonical 조회를 시작했고, 여기서
    //                     `applyLocal` 을 부르면 그 응답을 폐기해 버린다.
    final applyToCapacity = markChanged;
    if (applyToCapacity && widget.work != null) {
      // 기다리지 않는다 — 로컬 값으로 이미 화면은 맞다.
      //   microtask 라 아래 `applyLocal` 이 먼저 seq 를 올린 뒤 실행된다.
      Future.microtask(_loadCapacity);
    }

    try {
      final applications = _allApplications;

      final Map<String, Map<String, int>> newStats = {};
      int totalPending = 0;
      int totalConfirmed = 0;

      // [R7-P1-2 DEVICE.1E] 업무 목록은 카드와 같은 순서로 폴백한다.
      //
      //   여기는 `widget.toItem.workDetails` 하나만 봤다. 공고 카드가 단건/
      //   장기용으로 합성해 넘기는 TOItem 은 그 목록이 **비어 있다**. 그래서
      //   이 루프는 한 번도 돌지 않고 `newStats = {}` 가 되었고, 아래에서
      //   그 빈 map 이 `widget.toItem.workDetailStats` 를 **덮어썼다**.
      //
      //   이 함수는 initState 에서 `_loadApplicants` 직후에도 불린다 —
      //   즉 다이얼로그는 열리자마자 자기가 정원을 읽을 map 을 스스로
      //   지우고 있었다. 그것이 `정원 확인 불가` 의 실제 원인이다.
      //   (카드는 다음 build 에서 합성 item 을 새로 만들어 복구되지만,
      //    다이얼로그는 그 한 번의 snapshot 밖에 갖지 못한다)
      final details = widget.toItem.workDetails.isNotEmpty
          ? widget.toItem.workDetails
          : (widget.toItem.slot != null ? const <WorkDetailData>[] : widget.toItem.to.workDetails);

      // [R7-P1-2 DEVICE.1E] 좌석 규칙은 canonical 한 쪽만 쓴다.
      //
      //   여기는 status 만 봤다. `loadTOWorkDetails` 는 이미 반납 좌석과
      //   끝난 장기 약속을 빼고 센다. 같은 화면의 두 집계가 다른 규칙을
      //   쓰면, 확정 처리 한 번에 숫자가 조용히 갈라진다.
      final seatDay = _workApplicantsNow();
      // [R7-P1-2 DEVICE.1E.1] 좌석 규칙은 섹션 분류와 **같은 함수**다.
      bool countsAsSeat(ApplicationModel a) =>
          staffingRelationOf(a, seatDay).isCurrentStaffing;

      for (final work in details) {
        int pending = 0;
        int confirmed = 0;

        for (final app in applications) {
          // [E2-INVITED-SEAT] canonical wdId 를 먼저 본다 — 지원서 소속 판정
          //   (belongsToThisWork)·loadTOWorkDetails 와 같은 순서. 아래는 legacy.
          final bool matches;
          final wdId = app.workDetailId;
          final appWd = app.wdId;
          final workWd = work.wdId;
          if (appWd != null && appWd.isNotEmpty &&
              workWd != null && workWd.isNotEmpty) {
            matches = appWd == workWd;
          } else if (wdId != null && wdId.isNotEmpty) {
            if (wdId == work.id) {
              matches = true;
            } else if (wdId == work.workType) {
              // 레거시: workDetailId = workType만 → 시간으로 추가 확인
              matches = app.startTime == work.startTime &&
                  app.endTime == work.endTime;
            } else {
              matches = false;
            }
          } else {
            matches = app.selectedWorkType == work.workType &&
                app.startTime == work.startTime &&
                app.endTime == work.endTime;
          }
          if (matches && countsAsSeat(app)) {
            // [E2-INVITED-SEAT] `대기` 는 서버 PENDING_STATUSES(PENDING·INVITED).
            //   이 함수는 창이 **처음 열릴 때도** 돌고 그 값을 카드가 공유하는
            //   TOItem 에 덮어쓴다 — PENDING 만 세면 창을 한 번 열었다 닫은 카드가
            //   다음 build 에서 `대기 0` 이 됐다(설치 앱 실측).
            if (AppStatus.seatPendingStatuses.contains(app.status)) pending++;
            if (app.status == AppStatus.confirmed || app.status == AppStatus.contractPending) confirmed++;
          }
        }

        newStats[work.canonicalId] = {'pending': pending, 'confirmed': confirmed};
        totalPending += pending;
        totalConfirmed += confirmed;
      }

      // [R7-P1-2 DEVICE.1E] 아는 값을 **모르는 값으로** 덮지 않는다.
      //   셀 업무가 하나도 없었다면 이 계산은 정원에 대해 아무 말도 하지
      //   못한 것이다. 그때 빈 map 을 쓰면 UNKNOWN 을 만들어 낼 뿐이다.
      if (newStats.isNotEmpty) {
        widget.toItem.workDetailStats = newStats;
        // 슬롯 헤더 숫자도 즉시 갱신
        widget.toItem
            .updateOuterStats(confirmed: totalConfirmed, pending: totalPending);
        // [R7-P1-2 DEVICE.1E.1 §3] 이 화면의 정원도 같은 값으로 맞추되,
        //   **진행 중이던 canonical 응답을 무효화**한다. 그러지 않으면
        //   mutation 전에 나간 요청이 늦게 도착해 방금 확정한 사람을
        //   지워 버린다. 그 다음 canonical 재조회가 최종 권위를 되돌린다.
        if (applyToCapacity) _capacity.applyLocal(newStats);
      }
    } catch (e) {
      // 실패 시 현재 다이얼로그 목록 기준으로 현재 업무만 업데이트
      // [BUG-FIX] _applicants(필터된 Map 목록) → _allApplications(원본 ApplicationModel 목록) 사용
      // _applicants는 현재 업무(widget.work)로 필터된 결과라 전체 통계가 정확하지 않음
      int pending = 0;
      int confirmed = 0;

      // [R7-P1-2 DEVICE.1E] 폴백도 같은 좌석 규칙을 쓴다.
      final seatDay = _workApplicantsNow();
      for (final app in _allApplications) {
        if (!staffingRelationOf(app, seatDay).isCurrentStaffing) continue;
        if (AppStatus.seatPendingStatuses.contains(app.status)) pending++;
        if (app.status == AppStatus.confirmed || app.status == AppStatus.contractPending) confirmed++;
      }

      widget.toItem.workDetailStats ??= {};
      if (widget.work != null) {
        final entry = {'pending': pending, 'confirmed': confirmed};
        widget.toItem.workDetailStats![widget.work!.canonicalId] = entry;
        if (applyToCapacity) _capacity.applyLocal({widget.work!.canonicalId: entry});
      }
    }
  }
  /// [R7-PRE1A.1] 확인 문구·토스트에서 사람을 가리키는 표기.
  ///
  ///   `김지현(W-014)` — 동명이인이 있는 명단에서 관리자가 **무엇을 하려는지**
  ///   확인할 수 있어야 한다. 이름만 적으면 두 사람 중 어느 쪽인지 알 수 없다.
  ///   번호가 없으면 이름만 — 괄호만 남은 이름을 만들지 않는다.
  String _personLabelOf(UserModel? user, String fallback) =>
      user?.nameWithPersonNo ?? fallback;
}
