// 지원명단 다이얼로그 — 선택 날짜의 지원자(PENDING) + 확정자(CONFIRMED)
// 공고(TO) → 업무상세별로 묶어서 표시, work_applicants_dialog 카드 스타일 준용
import 'dart:math' show min;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/business_model.dart';
import '../../../models/core/employment_contract_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_data.dart';
import '../../../models/core/business_member_model.dart';
import '../../../providers/user_provider.dart';
import '../../../screens/common/settings_screen.dart';
import '../../../screens/contract/contract_sign_screen.dart' show ContractTemplateWidget;
import '../../../services/contract_service.dart';
import '../../../services/business_posting_readiness.dart';
import '../../../services/firestore_service.dart';
import '../../../services/invite_save_verifier.dart';
import 'day_applicants_reads.dart';
import '../../../utils/text_layout.dart';
import '../../../widgets/common/adaptive_action_row.dart';
import '../../../utils/person_label.dart';
import '../../../utils/id_card_helper.dart';
import '../../../utils/contract_attendance_gate.dart';
// trust_score_helper: 신뢰도 점수 시스템 제거 (5A.2A)
import '../../../theme/app_colors.dart';
import '../../../utils/action_guard.dart';
import '../../../utils/dialog_helper.dart';
import '../../../models/ui/day_staffing_row.dart';
import '../../../models/ui/invite_capacity_state.dart';
// [ISG2-REFRESH] 초대 결과 → 전파·재조회 판단 한 곳.
import '../../../models/ui/invite_refresh_outcome.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/posting_readiness_reason.dart';
import '../../../widgets/admin/invite_state_label.dart';
import '../../../widgets/dialogs/application_policy_acknowledge_sheet.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/week_helper.dart';
import '../../../widgets/app_select_field.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/admin/applicant_row_surface.dart';
import '../../../widgets/admin/contract_attendance_unknown_notice.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../models/core/contract_template_model.dart' show ContractArticle;
import '../../../widgets/dialogs/contract_template_selector_dialog.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../widgets/dialogs/alternative_work_offer_sheet.dart';
import 'available_workers_bottom_sheet.dart';
import 'invite_method_sheet.dart';
import 'invite_worker_dialog.dart';

// ─── 그룹 데이터 (업무 단위) ────────────────────────────────────────────────
/// [UI-SCREEN-CONSISTENCY.1] 행 버튼의 역할 — _actionButton 참고.
enum _ActionRole { primary, secondary, destructive, urgent }

class _GroupData {
  final String? toId;
  final String toTitle;
  final String workType;
  final String startTime;
  final String endTime;
  /// [R7-P1-PRODUCT] canonical row가 오면 덮어쓴다 — final이 아니다.
  ///   지원서에서 유도한 값보다 서버가 준 공고 type이 우선이다.
  bool isLongTerm;

  /// [R7-P1R §14] 장기 초대가 만들어야 하는 약속 범위 — canonical row에서 온다.
  DateTime? workEndDate;
  List<String> workDays = const [];
  /// [8.1E.4] canonical workDetail ID (wdId, new-schema 슬롯)
  final String? wdId;
  final String? workDetailId;   // composite WorkDetail ID (레거시/capacityKey 용)
  int requiredCount;             // 나중에 채움
  /// [R8-P7.3] 정원을 실제로 읽었는가.
  ///   슬롯 정원 조회가 실패하면 requiredCount 가 0 으로 남는데,
  ///   그건 "정원 0"이 아니라 "모른다"다. 둘을 갈라 놓지 않으면
  ///   화면이 "확정 N / 0"이라고 단정한다.
  bool requiredCountKnown;
  /// [R2] slot canonical id. 지원자가 0명인 모집 단위에서도 초대 CTA가 서려면
  /// slotId를 지원서에서 유도하면 안 된다 — slot 자신이 알려줘야 한다.
  String? slotId;
  final List<ApplicationModel> pendingApps = [];
  final List<ApplicationModel> confirmedApps = [];

  /// [R2.2] 아직 응답하지 않은 초대. pendingApps와 합치지 않는다 —
  /// 지원은 지원자가 표시한 관심이고 초대는 관리자가 먼저 보낸 제안이다.
  final List<ApplicationModel> invitedApps = [];

  /// [R2.2] 응답·종료된 초대 (거절·철회·만료·자동종료). 최근 것만 보여준다.
  final List<ApplicationModel> closedInvites = [];

  /// [R2.2.1] 수락되어 자리를 가져간 초대 (CONFIRMED/CONTRACT_PENDING + invitedAt).
  ///
  ///   확정자 명단에만 있으면 그 사람이 스스로 지원해 승인된 것인지 관리자가
  ///   초대해 수락한 것인지 구분할 수 없다. 초대를 보낸 쪽은 그 초대가 어떻게
  ///   끝났는지 알아야 한다. 새 status enum 없이 invitedAt으로 구분한다 —
  ///   invitedAt은 callableInviteWorker만 쓰고 수락 시에도 지워지지 않는다.
  final List<ApplicationModel> acceptedInvites = [];

  /// [R2.2.1] slot이 말하는 확정 수 — `workDetailCounts[wdId].confirmedCount`.
  ///
  ///   근로자 화면의 `workInstanceFull`이 쓰는 **바로 그 값**이다. 지원서에서
  ///   세지 않는다. null = 이 모집 단위의 canonical row가 없다(UNKNOWN).
  int? canonicalConfirmed;

  /// [R2 FINAL] slot이 말하는 **종료** 여부. 정원이 찬 것과 다른 사실이다.
  bool canonicalClosed = false;

  /// [INVITE-CLOSURE-PROJECTION] 이 단위에 이미 발송된 초대가 **끝났는가**.
  ///   [canonicalClosed](공개 모집 종료)와 다르다 — 공개 지원 접수만 자동
  ///   마감된 단위의 초대는 기한까지 수락될 수 있다. 서버 row 가 말한다.
  bool canonicalInviteEnded = false;

  /// 공개 모집은 끝났지만 이미 보낸 초대는 살아 있는 단위인가.
  bool get invitesOutliveIntake => canonicalClosed && !canonicalInviteEnded;

  /// [INVITE-TERMINAL] 서버가 읽은 시각 기준 **새 초대**를 보낼 수 있는가.
  bool canonicalInviteOpen = false;

  /// [INVITE-TERMINAL] 공개 지원은 자동 마감됐지만 인력 초대는 가능한 단위의 부족.
  ///   공개 부족([shortage])은 0 이다(채울 공개 모집이 없다). 이 값은 초대 CTA
  ///   한 곳만 쓴다 — 통계·헤더의 부족을 다시 열지 않는다.
  int get privateInviteShortage {
    if (!invitesOutliveIntake || !canonicalInviteOpen) return 0;
    return staffingShortageOf(
          capacity: inviteCapacityState,
          requiredCount: requiredCount,
          seatedConfirmed: seatedConfirmed,
        ) ??
        0;
  }

  /// [INVITE-CLOSURE-PROJECTION] **초대**의 지금 상태 — 서버 수락 tx 와 같은 판정.
  ///
  ///   [capacityState] 는 공개 모집(부족·초대 CTA)의 상태라 그대로 둔다 —
  ///   공개 지원이나 새 초대 버튼을 다시 열지 않는다. 초대 행만 이 값을 쓴다:
  ///   자동 접수 마감이면 종료가 아니라 단위 정원(찼는가)으로 본다.
  InviteCapacityState get inviteCapacityState {
    if (!invitesOutliveIntake) return capacityState;
    if (!requiredCountKnown) return InviteCapacityState.unknown;
    return inviteCapacityStateOf(
      canonicalConfirmed: canonicalConfirmed,
      requiredCount: requiredCount,
      isClosed: false,
    );
  }

  _GroupData({
    required this.toId,
    required this.toTitle,
    required this.workType,
    required this.startTime,
    required this.endTime,
    required this.isLongTerm,
    this.wdId,
    this.workDetailId,
    this.requiredCount = 0,
    this.requiredCountKnown = true,
    this.slotId,
  });

  // 공고 고유 키 (공고 헤더 그룹핑용)
  String get toKey => toId ?? 'noid_$toTitle';

  // [8.1E.4] 업무 고유 키 — wdId 우선, composite fallback, legacy fallback
  String get groupKey {
    final wKey = wdId?.isNotEmpty == true
        ? wdId!
        : (workDetailId?.isNotEmpty == true
            ? workDetailId!
            : '${workType}_${startTime}_$endTime');
    return '${toId ?? toTitle}_$wKey';
  }

  // capacity 맵에서 찾을 때 사용할 키 (composite 기반 _workDetailCapacityMap 과 일치)
  String get capacityKey => workDetailId?.isNotEmpty == true
      ? workDetailId!
      : '${workType}_${startTime}_$endTime';

  /// [R2.2.1 CORRECTION] 이 모집 단위가 지금 초대를 받을 수 있는가 — 세 상태.
  ///
  ///   `bool?`로 두었더니 호출부가 `!= true`라고 쓸 수 있었고, Dart에서
  ///   `null != true`는 true라 UNKNOWN이 `자리 있음`으로 새어 들어갔다.
  ///   enum은 세 갈래를 각각 쓰지 않고는 분기할 수 없게 만든다.
  ///
  ///   근로자 화면의 `workInstanceFull`과 같은 식을 쓴다 — 관리자가 다른 식을
  ///   쓰면 한쪽은 `수락 불가`, 다른 쪽은 `초대 중`이 되는 모순이 생긴다.
  InviteCapacityState get capacityState => requiredCountKnown
      // [R8-P7.3] 정원을 못 읽었으면 자리가 남았는지도 찼는지도 말할 수 없다.
      //   기존 UNKNOWN 계약에 그대로 태운다 — 새 상태를 만들지 않는다.
      ? inviteCapacityStateOf(
          canonicalConfirmed: canonicalConfirmed,
          requiredCount: requiredCount,
          isClosed: canonicalClosed,
        )
      : InviteCapacityState.unknown;

  /// capacity를 알고 있고 자리가 남았다 — 이것만 `초대 중`이다.
  List<ApplicationModel> get activeInvites =>
      inviteCapacityState == InviteCapacityState.available ? invitedApps : const [];

  /// 자리가 **다 찼다**.
  ///
  ///   상태는 INVITED 그대로 둔다. 자리가 다시 열리면 다시 수락 가능해지는
  ///   현재 정책을 보존해야 하므로, 표시 때문에 CANCELED로 바꾸지 않는다.
  List<ApplicationModel> get staleInvites =>
      inviteCapacityState == InviteCapacityState.full ? invitedApps : const [];

  /// 모집이 **종료됐다**. 자리가 남아 있어도 더 이상 뽑지 않는다.
  ///
  ///   `closedInvites`(거절·철회·만료된 초대 기록)와 다른 개념이다.
  ///   여기 있는 초대는 아직 INVITED이고, 끝난 것은 초대가 아니라 모집이다.
  List<ApplicationModel> get unitClosedInvites =>
      inviteCapacityState == InviteCapacityState.closed ? invitedApps : const [];

  /// [SYSTEM-INTEGRATION-R2.4 §4/§19] 이 모집 단위의 **자리를 차지한** 확정 수.
  ///
  ///   NO_SHOW 대체충원으로 좌석을 반납한 확정(`staffingReleasedAt`)은 status가
  ///   CONFIRMED로 남지만 정원을 소모하지 않는다. canonical
  ///   `workDetailCounts.confirmedCount`도 그때 함께 내려간다.
  int get seatedConfirmed =>
      confirmedApps.where((a) => !a.isStaffingReleased).length;

  /// [SYSTEM-INTEGRATION-R2.4 §4/§5] 부족 — 이 화면의 **모든** 표면이 이것만 쓴다.
  ///
  ///   이전에는 통계 스트립·초대 CTA·초대 방법 시트가 각자 계산했다.
  ///   식이 조금씩 달라 같은 다이얼로그 안에서 `부족 2`라고 적힌 버튼을 눌렀는데
  ///   열린 시트는 `부족 1`이라고 말할 수 있었다.
  ///
  ///   · 초대(INVITED)는 빼지 않는다 — 초대는 자리를 확보하지 않는다.
  ///   · 대기(PENDING)도 빼지 않는다 — 같은 이유.
  ///   · 종료된 모집 단위는 채울 수 없으므로 부족이 아니다
  ///     (callableGetStaffingReadiness·DayStaffingRow.shortage와 같은 계약).
  ///   [R7-P1-3] 식 자체는 `staffingShortageOf`가 갖는다 — WorkApplicantsDialog가
  ///   같은 모집 단위를 열 때 여기 있는 식을 다시 쓰기 위해서다.
  ///   이 getter는 UNKNOWN을 0으로 내리지 않는다: 호출부가 이미
  ///   `isCapacityUnknown`을 따로 분기하고 있고, 그 경로에서 CTA는 서지 않는다.
  int get shortage =>
      staffingShortageOf(
        capacity: capacityState,
        requiredCount: requiredCount,
        seatedConfirmed: seatedConfirmed,
      ) ??
      0;

  /// capacity를 모른다 — 수락 가능한지도 찼는지도 말할 수 없다.
  List<ApplicationModel> get unknownInvites =>
      inviteCapacityState == InviteCapacityState.unknown ? invitedApps : const [];

  /// 인력 현황을 읽지 못해 충원 판단을 할 수 없는 상태.
  bool get isCapacityUnknown =>
      capacityState == InviteCapacityState.unknown;
}

// ─── 다이얼로그 ────────────────────────────────────────────────────────────────
class DayApplicantsDialog extends StatefulWidget {
  final DateTime date;
  final List<String> businessIds;
  final List<BusinessModel> businesses;
  /// 특정 공고로 필터링 (TOGroupCard 명단 보기에서 사용). null이면 전체 표시.
  final String? filterToId;

  /// [R8 O03] 읽기 경계. 주지 않으면 실제 서비스로 간다.
  ///   화면의 계산(그룹 구성·머리말·scope label)은 그대로 이 위젯이 한다.
  final DayApplicantsReads? reads;

  const DayApplicantsDialog({
    super.key,
    required this.date,
    required this.businessIds,
    required this.businesses,
    this.filterToId,
    this.reads,
  });

  @override
  State<DayApplicantsDialog> createState() => _DayApplicantsDialogState();
}

class _DayApplicantsDialogState extends State<DayApplicantsDialog> {
  final FirestoreService _svc = FirestoreService();
  late final DayApplicantsReads _reads =
      widget.reads ??
      DayApplicantsReads.debugOverride ??
      DayApplicantsReads.of(_svc);

  bool _isLoading = true;
  bool _isProcessing = false;

  /// [BULK-PROGRESS] 일괄 처리 진행 상황 — null이면 진행 중 아님.
  /// 순차 처리라 인원에 비례해 걸리므로 몇 명째인지 보여 준다.
  ({int done, int total})? _batchProgress;
  bool _hasChanges = false;
  String? _selectedBusinessId;

  // [POSTING-V2-02G.1] 권한은 **이 다이얼로그가 보고 있는 사업장** 기준이다.
  //
  // UserProvider.can()은 Shell에서 선택한 사업장의 권한이라, 여기서 다른
  // 사업장의 지원자를 보고 있으면 실행 불가능한 액션이 활성화된다.
  // 서버는 confirm/reject/cancel 모두 대상 사업장의 canManageTo를 요구한다.
  // 사업장을 특정할 수 없을 때만 기존 판정으로 폴백한다.
  bool _canForSelectedBiz(bool Function(MemberPermissions p) check) {
    final up = Provider.of<UserProvider>(context, listen: false);
    final bizId = _selectedBusinessId;
    if (bizId == null || bizId.isEmpty) return up.can(check);
    return up.canForBusiness(bizId, check);
  }

  List<ApplicationModel> _pendingApps = [];
  List<ApplicationModel> _confirmedApps = [];
  List<_GroupData> _cachedGroups = [];
  Map<String, UserModel> _userMap = {};
  // [REISSUE-RECOVERY] 조회 실패(unresolved)와 "계약 없음"을 구별해 담는다.
  ContractStatusBatch _contractStatusMap = const ContractStatusBatch();

  /// [REISSUE-RECOVERY] **지금 이 지원서에 계약서를 보내는 것이 행동인가.**
  ///
  ///   두 사실의 곱이다.
  ///     · 계약서가 **없다고 확인됐다** — 조회 실패는 아니다(ERROR ≠ ZERO)
  ///     · 보낼 수 있는 관계다 — 좌석 반납·해지 승인은 제외
  ///       (서버 `srvNeedsContractIssue` 와 같은 한 벌: `isContractIssuable`)
  ///
  ///   미발송 탭·홈 할 일은 그 서버 판정을 쓴다. 이 다이얼로그가 다른 조건을
  ///   쓰면 같은 사실을 두 화면이 다르게 말한다.
  ///   [NOSHOW-CONTRACT-GUARD] 세 번째 사실 — 그 근무일 근태가 노쇼·결근이 아니다
  ///   (서버 `srvContractBlockedByAttendance` 와 같은 규칙, 근태를 모르면 단기는 아니다).
  /// [CONTRACT-BEFORE-CHECKIN] 다시 읽은 목록에서 그 확정자 — 확정 직후 계약 작성으로 넘길 최신 지원서.
  ApplicationModel? _confirmedAppById(String id) {
    for (final g in _buildGroups()) {
      for (final a in g.confirmedApps) {
        if (a.id == id) return a;
      }
    }
    return null;
  }

  bool _needsContractIssue(ApplicationModel app) =>
      _contractStatusMap.isMissingContract(app.id) &&
      app.isContractIssuable &&
      ContractAttendanceGate.clearForIssue(app, _contractBlockedAppIds);

  /// [DIALOG-VISUAL-CLOSE] 계약서가 없는 확정 행의 배지 — `계약서 작성` 버튼과 같은 판정.
  ///   · 발행할 수 있다 → `계약서 작성 필요`(지금 할 수 있는 다음 일, orange)
  ///   · 단기인데 근태를 못 읽었다 → `근태 확인 필요`(위 안내의 `다시 시도`가 할 일)
  ///   · 노쇼·결근 근무일·좌석 반납·해지 → `계약 대상 아님`(기록, gray)
  ({IconData icon, String label, Color color}) _missingContractChip(
      ApplicationModel app) {
    if (_needsContractIssue(app)) {
      return (
        icon: Icons.assignment_late_outlined,
        label: '계약서 작성 필요',
        color: AppColors.warningDark,
      );
    }
    if (app.isContractIssuable &&
        _contractBlockedAppIds == null &&
        ContractAttendanceGate.attendanceDocId(app) != null) {
      return (
        icon: Icons.help_outline,
        label: '근태 확인 필요',
        color: AppColors.grey600,
      );
    }
    return (
      icon: Icons.do_not_disturb_alt_outlined,
      label: '계약 대상 아님',
      color: AppColors.grey600,
    );
  }

  /// [NOSHOW-CONTRACT-GUARD] 노쇼·결근으로 기록된 지원서 id. null = 근태를 읽지 못했다.
  Set<String>? _contractBlockedAppIds;
  bool _contractAttRetrying = false;

  /// 근태를 몰라서 `계약서 작성` 을 **내지 않은** 행이 있는가 — 그때만 안내한다.
  bool get _contractAttendanceSuppressed =>
      _contractBlockedAppIds == null &&
      _canForSelectedBiz((p) => p.canManageContract) &&
      _confirmedApps.any((a) =>
          _contractStatusMap.isMissingContract(a.id) &&
          a.isContractIssuable &&
          ContractAttendanceGate.attendanceDocId(a) != null);

  /// 근태만 다시 읽는다(명단 전체를 다시 부르지 않는다).
  Future<void> _retryContractAttendance() async {
    final bizId = _selectedBusinessId;
    final read = _reads.contractAttendances;
    if (bizId == null || read == null || _contractAttRetrying) return;
    setState(() => _contractAttRetrying = true);
    Set<String>? blocked;
    try {
      blocked = ContractAttendanceGate.blockedIds(
          _confirmedApps, await read(businessId: bizId, date: widget.date));
    } catch (e) {
      debugPrint('⚠️ [NOSHOW-CONTRACT-GUARD] 근태 재조회 실패: $e');
      blocked = null;
    }
    if (!mounted || _selectedBusinessId != bizId) return;
    setState(() {
      _contractBlockedAppIds = blocked;
      _contractAttRetrying = false;
    });
  }
  Map<String, int> _weeklyWorkCountMap = {};
  Map<String, int> _workDetailCapacityMap = {};
  /// [R8-P7.3] 정원을 읽지 못했다 — "정원 0"과 다른 상태다.
  bool _capacityUnknown = false;

  /// [UI-APPLICANTS-AND-INVITATIONS.2] 슬롯별 업무 id — 정원 표시를 위해 **이미** 읽는 응답에서 함께 기억한다.
  ///   키 '${toId}|${slotId}'. 없으면 모른다(읽기 실패·다른 슬롯) — 그때는 제안 버튼을 지금처럼 둔다.
  Map<String, Set<String>> _slotWorkDetailIds = {};

  /// 이 지원서의 슬롯에 **다른 업무가 없다고 확실할 때만** true. 이름이 같아도 시간대·id 가 다르면 다른 업무다
  ///   (id 로만 센다). 표시 편의일 뿐이다 — 제안하면 서버가 다시 판정한다.
  bool _surelyNoOtherWork(ApplicationModel app) {
    final ids = _slotWorkDetailIds['${app.toId}|${app.slotId}'];
    if (ids == null || ids.isEmpty) return false;
    final own = app.wdId?.isNotEmpty == true ? app.wdId : app.workDetailId;
    return ids.length == 1 && own != null && ids.contains(own);
  }

  // [SYSTEM-INTEGRATION-R2] 이 날짜의 FLEX 모집 단위 전체 (slot canonical).
  //
  //   그룹을 지원서에서만 만들면 지원자가 0명인 모집 단위는 그룹 자체가 생기지
  //   않는다. Home이 `3명 부족 ›`이라고 보내 놓고 다이얼로그는 비어 있고,
  //   부족을 해결할 `인력 초대` 버튼도 함께 사라진다 — 부족이 가장 심한 상태에서
  //   해결 수단이 없어진다. 부족은 지원서가 아니라 slot capacity에 속한다.
  //
  //   null = 조회 실패(UNKNOWN). 빈 목록(성공)과 구분한다 —
  //   실패를 빈 목록으로 바꾸면 `충원할 것이 없다`는 거짓 주장이 된다.
  List<DayStaffingRow>? _dayStaffingRows = const [];

  /// [SYSTEM-INTEGRATION-R2.2] 이 날짜의 초대 현황.
  ///
  ///   초대를 보낸 뒤 관리자가 그 결과를 볼 곳이 없었다. INVITED Application은
  ///   만들어지고 자리의 pendingCount도 올라가는데, 관리자 화면 어디에도
  ///   `INVITED`를 읽는 곳이 없었다 — 누구에게 보냈는지, 몇 건이 응답을
  ///   기다리는지, 누가 거절했는지를 알 수 없었다.
  ///
  ///   null = 조회 실패(UNKNOWN). `초대 중 0명`으로 바꾸지 않는다.
  List<ApplicationModel>? _dayInvitations = const [];

  final Set<String> _selectedIds = {};
  final Set<String> _starredIds = {};
  Map<String, String> _idCardStatusMap = {};
  // [BUG-CANCEL-01] 근무 이력 있는 확정자에게 확정취소 버튼 노출 방지용 맵
  // key = userId, value = 오늘 날짜에 checkIn 기록 존재 여부
  Map<String, bool> _hasWorkedMap = {};
  // [R5.1 NO_SHOW 대체충원] 당일 NO_SHOW 상태인 출근 기록의 applicationId 집합
  // "대체 인력 충원" 버튼 표시 조건에 사용
  Set<String> _noShowApplicationIds = {};
  // 파트변경 다이얼로그용 TO 캐시 — 같은 TO 재탭 시 서버 읽기 생략
  final Map<String, TOModel> _toCache = {};
  bool _isBatchMode = false;
  // BUG-1 수정: 전역 bool → 그룹 key로 스코프화.
  // 전역이면 다중 그룹 시 그룹A 선택 모드가 그룹B UI에도 반영됨.
  String? _idCardSelectGroupKey;       // null = 선택 모드 없음
  final Set<String> _selectedIdCardUserIds = {};
  // BUG-3 수정: 동일 이유로 전역 bool → 그룹 key 스코프화.
  String? _contractBatchGroupKey;      // null = 처리 중 없음

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // [특이사항] businessIds는 반드시 _getAdminBusinesses()가 반환한 서버 검증 목록만 전달해야 한다.
    // 다이얼로그 내부에서 businessId 소속 재검증을 하지 않으므로,
    // 호출부가 신뢰할 수 없는 출처의 ID를 전달하면 크로스-사업장 쿼리가 실행된다.
    _selectedBusinessId =
        widget.businessIds.isNotEmpty ? widget.businessIds.first : null;
    _applySavedBusinessThenLoad();
  }

  Future<void> _applySavedBusinessThenLoad() async {
    if (widget.businessIds.length > 1) {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('alfit_last_business_id');
      if (saved != null && widget.businessIds.contains(saved) && mounted) {
        setState(() => _selectedBusinessId = saved);
      }
    }
    if (!mounted) return;
    _load();
  }

  // [CROSS-DOMAIN-R5.1F.2] 이 다이얼로그가 보고 있는 사업장은 selected와 다를
  //   수 있고, 사업장 선택기로 바뀌기도 한다. 보고 있는 **하나만** 구독하고,
  //   바뀌면 구독을 옮겨 단다. 닫히면 끊는다 — 상시 구독이 아니다.
  String? _watchedBizId;
  VoidCallback? _releasePermsWatch;

  void _watchPermsFor(String? bizId) {
    if (_watchedBizId == bizId) return;
    _releasePermsWatch?.call();
    _releasePermsWatch = null;
    _watchedBizId = bizId;
    if (bizId == null || !mounted) return;
    _releasePermsWatch =
        context.read<UserProvider>().watchBusinessPermissions(bizId);
  }

  @override
  void dispose() {
    _releasePermsWatch?.call();
    super.dispose();
  }

  String _bizName(String? bizId) {
    if (bizId == null) return '';
    for (final b in widget.businesses) {
      if (b.id == bizId) return b.name;
    }
    return bizId;
  }

  Future<void> _load() async {
    final bizId = _selectedBusinessId;
    // 사업장이 정해지는 유일한 길목이다 — 여기서 구독 대상을 맞춘다.
    _watchPermsFor(bizId);
    if (bizId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _isLoading = true;
      _selectedIds.clear();
      _starredIds.clear();
      _idCardStatusMap = {};
      _hasWorkedMap = {}; // [BUG-CANCEL-01] 로드 시작 시 초기화 — 이전 날짜 잔류 방지
      _capacityUnknown = false; // [R8-P7.3] 이번 로드의 판정으로 다시 정한다
      _slotWorkDetailIds = {}; // [UI-APPLICANTS-AND-INVITATIONS.2] 이번 로드의 응답으로만
      _noShowApplicationIds = {}; // [R5.1] 초기화
      _contractBlockedAppIds = null; // [NOSHOW-CONTRACT-GUARD] 이번 로드가 다시 읽는다
      _contractAttRetrying = false;
      _toCache.clear();   // 파트변경 후 재로드 시 TO 캐시 무효화
      _isBatchMode = false;
      _idCardSelectGroupKey = null;
      _selectedIdCardUserIds.clear();
      _contractBatchGroupKey = null;
    });

    try {
      // Phase 1: 지원자 + 확정자 병렬 조회
      // [R8-P7.2] 확정자는 OrThrow 변형을 쓴다. 이 목록이 그날 누가 일하는지를
      //   말하는 자리라, 조회 실패를 "확정자 없음"으로 보여 주면 안 된다.
      //   _load() 의 catch 가 오류 토스트를 띄운다.
      // [R2] 이 날짜의 FLEX 모집 단위 — 지원서와 별개로 slot에서 읽는다.
      //   실패해도 지원자 명단은 유효하므로 전체를 ERROR로 만들지 않고,
      //   충원 영역만 UNKNOWN으로 내린다 (ERROR != ZERO).
      List<DayStaffingRow>? staffingRows;

      // [R2.2] 초대 현황 — 지원자 목록과 별개로 읽는다.
      //   실패해도 지원자 명단은 유효하므로 초대 영역만 UNKNOWN으로 내린다.
      //
      //   canManageTo가 없으면 아예 조회하지 않는다. 그 권한이 없는 관리자는
      //   초대를 보낼 수도 없고(CTA도 같은 권한으로 막혀 있다), 서버도 거부한다.
      //   권한 없음을 `확인하지 못했어요`(ERROR)로 표시하지 않기 위해
      //   빈 목록으로 둔다 — NO_PERMISSION != ERROR.
      List<ApplicationModel>? invitations = const [];
      final canSeeInvites = _canForSelectedBiz((p) => p.canManageTo);

      // [R8-PERFORMANCE.1] 충원·초대는 **이전 결과를 쓰지 않는다** —
      //   필요한 입력은 사업장과 날짜뿐이다. 그런데 각자 자기 라운드를
      //   차지하고 있어서, 지원자 목록이 돌아온 뒤에야 출발했다.
      //   DEV 실측에서 dayStaffing 혼자 웜 920ms(이번 감사 최장)였고,
      //   콜드에서는 함수별 콜드스타트가 라운드마다 더해졌다.
      //
      //   그래서 같은 라운드로 옮긴다. 다만 **실패는 합치지 않는다.**
      //   `Future.wait` 는 하나가 던지면 나머지 성공분까지 버리므로,
      //   둘을 각자 try/catch 를 가진 클로저로 감싸 자기 칸만 UNKNOWN 으로
      //   내린다(급여 화면이 쓰는 것과 같은 형태).
      //   지원자·확정자는 감싸지 않는다 — 그 둘의 실패는 지금처럼
      //   바깥 catch 가 받아 화면 전체 ERROR 가 맞다.
      final (dayStart, _) = FormatHelper.kstDayRange(widget.date);
      final phase1 = await Future.wait<Object?>([
        // [R7-P1-2.2] 대기 지원자는 **검토 대상**이다 — 서버가 canManageTo 를
        //   보도록 purpose 를 넘긴다. 이 화면의 확정·거절 CTA 가 쓰는 권한과 같다.
        _reads.pendingApplications(
            date: widget.date,
            businessId: bizId,
            purpose: FirestoreService.purposeApplicantReview),
        // 확정 근무자 명단은 purpose 를 넘기지 않는다. Home·근무 운영 화면이
        //   같은 reader 를 쓰고, 그쪽은 canManageWorkers 로 보는 것이 정상이다.
        //   여기서 canManageTo 를 요구하면 그 화면들이 함께 깨진다.
        _reads.confirmedWorkers(
            date: widget.date, businessId: bizId),
        () async {
          try {
            var rows = await _reads.dayStaffing(
              businessId: bizId,
              dayStartMs: dayStart.millisecondsSinceEpoch,
            );
            if (widget.filterToId != null) {
              rows = rows.where((r) => r.toId == widget.filterToId).toList();
            }
            staffingRows = rows;
          } catch (e) {
            debugPrint('⚠️ [DayApplicants] 인력 현황 조회 실패: $e');
            staffingRows = null;
          }
          return null;
        }(),
        () async {
          if (!canSeeInvites) return null;
          try {
            var list = await _reads.dayInvitations(
                date: widget.date, businessId: bizId);
            if (widget.filterToId != null) {
              list = list.where((a) => a.toId == widget.filterToId).toList();
            }
            invitations = list;
          } catch (e) {
            debugPrint('⚠️ [DayApplicants] 초대 현황 조회 실패: $e');
            invitations = null;
          }
          return null;
        }(),
      ]);
      var pending = phase1[0] as List<ApplicationModel>;
      var confirmed = phase1[1] as List<ApplicationModel>;

      // 특정 공고 필터 (TOGroupCard 명단 보기)
      if (widget.filterToId != null) {
        pending = pending.where((a) => a.toId == widget.filterToId).toList();
        confirmed = confirmed.where((a) => a.toId == widget.filterToId).toList();
      }

      if (!mounted || _selectedBusinessId != bizId) return;

      // Phase 2: 유저 프로필 + 계약서 상태 + 주간 근무횟수 병렬 조회
      final allApps = [...pending, ...confirmed];
      Map<String, UserModel> userMap = {};
      ContractStatusBatch contractMap = const ContractStatusBatch();
      Map<String, int> weeklyMap = {};

      if (allApps.isNotEmpty) {
        // [R2.2] 초대받은 사람의 이름도 필요하다 — 초대 현황이 uid만 보여주면
        //   `누구에게 보냈는가`를 답하지 못한다. 계약서·주간 횟수는 지원/확정자
        //   대상이므로 그쪽 목록은 늘리지 않는다.
        final allUids = {
          ...allApps.map((a) => a.uid),
          ...(invitations ?? const <ApplicationModel>[]).map((a) => a.uid),
        }.toList();
        final allAppIds = allApps.map((a) => a.id).toList();

        // Phase 3 입력값은 Phase 1 결과만 필요 → Phase 2와 병렬로 선제 시작
        final confirmedUserIds = confirmed.map((a) => a.uid).toSet().toList();
        final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

        final idCardFuture = (confirmedUserIds.isNotEmpty && currentUserId.isNotEmpty)
            ? IdCardHelper.loadStatusBatch(
                firestoreService: _svc,
                requesterId: currentUserId,
                targetUserIds: confirmedUserIds,
              )
            : Future.value(<String, String>{});

        // [R7-P1-4 §11] 리뷰 작성 여부 조회 제거 — 확정자 1명당 1 read였고,
        //   그 결과로 만든 배지가 근무 전 확정자에게 없는 업무를 만들었다.

        final hasWorkedFuture = confirmedUserIds.isNotEmpty
            ? _reads.hasWorkedMap(businessId: bizId, date: widget.date)
            : Future.value(<String, bool>{});

        // [R5.1] NO_SHOW applicationId 집합 선제 시작 (Phase 2와 병렬)
        final noShowFuture = _reads.noShowApplicationIds(
          businessId: bizId, date: widget.date);

        // [NOSHOW-CONTRACT-GUARD] 계약 발행 판정용 근태(실패·상한 도달은 던지는 읽기).
        //   실패해도 화면 전체를 실패로 만들지 않는다. 대신 근태를 모른다고 두고 안내한다.
        final Future<List<AttendanceModel>?>? contractAttFuture = _reads
            .contractAttendances
            ?.call(businessId: bizId, date: widget.date)
            .then<List<AttendanceModel>?>((v) => v, onError: (Object e) {
          debugPrint('⚠️ [NOSHOW-CONTRACT-GUARD] 근태 조회 실패 — 계약 발행 판정 보류: $e');
          return null;
        });

        // Phase 2: Phase 3 futures가 이미 실행 중인 상태에서 병렬로 처리됨
        Map<String, int> workDetailCapacityMap = {};
        final results = await Future.wait([
          // [PII-DOC-R0.1 / INV-1] 날짜별 지원자·확정자 목록 — 계좌 불필요.
          _reads.usersBatch(allUids, businessId: bizId,
              purpose: FirestoreService.purposeWorkerDirectory),
          _reads.contractStatusBatch(allAppIds, businessId: bizId),
          _loadWeeklyCount(bizId),
          _loadWorkDetailCapacities(allApps),
          // [4J.0C] 대기 중 TO 모델 선제 로드 — canApprovePending UI gate용
          _fetchToCacheForPending(pending),
        ]);
        userMap = results[0] as Map<String, UserModel>;
        contractMap = results[1] as ContractStatusBatch;
        weeklyMap = results[2] as Map<String, int>;
        workDetailCapacityMap = results[3] as Map<String, int>;

        // Phase 3 결과 수집 (Phase 2와 병렬로 이미 실행 완료됐을 가능성 높음)
        final idCardMap = await idCardFuture;

        // [BUG-CANCEL-01] 당일 근무 여부 맵 — 확정취소 버튼 가드용
        final hasWorkedMap = await hasWorkedFuture;

        // [R5.1] NO_SHOW applicationId 집합 수집
        final noShowApplicationIds = await noShowFuture;

        // null = 근태를 모른다(주지 않았거나 실패) — 단기 근무에 계약서를 권하지 않는다.
        final contractBlocked = ContractAttendanceGate.blockedIds(
            confirmed, contractAttFuture == null ? null : await contractAttFuture);

        final starredFromFirestore =
            allApps.where((app) => app.isStarred).map((app) => app.id).toSet();

        if (!mounted || _selectedBusinessId != bizId) return;
        setState(() {
          _pendingApps = pending;
          _confirmedApps = confirmed;
          _userMap = userMap;
          _contractStatusMap = contractMap;
          _weeklyWorkCountMap = weeklyMap;
          _workDetailCapacityMap = workDetailCapacityMap;
          // 성공 경로에서만 UNKNOWN 을 내린다.
          _dayStaffingRows = staffingRows;
          _dayInvitations = invitations;
          _idCardStatusMap = idCardMap;
          _starredIds.addAll(starredFromFirestore);
          _hasWorkedMap = hasWorkedMap; // [BUG-CANCEL-01]
          _noShowApplicationIds = noShowApplicationIds; // [R5.1]
          _contractBlockedAppIds = contractBlocked; // [NOSHOW-CONTRACT-GUARD]
          _isLoading = false;
          _rebuildGroups();
        });
        return;
      }

      // [INVITE-PREACCEPT] 지원·확정이 없고 **초대만 있는 날**에도 초대받은
      //   사람이 누구인지 읽는다. 예전에는 위 분기에서만 읽어서, 초대만 있는
      //   날의 초대 행이 이름 없이 `근무자`로 보였고 상세(서류 확인)로 갈 수도
      //   없었다(DEV 실측 공고가 정확히 이 경우였다). 실패는 이름만 비게 둔다 —
      //   초대 현황 자체를 실패로 만들지 않는다.
      final inviteOnlyUids = {
        ...(invitations ?? const <ApplicationModel>[]).map((a) => a.uid),
      }.toList();
      if (inviteOnlyUids.isNotEmpty) {
        try {
          userMap = await _reads.usersBatch(inviteOnlyUids, businessId: bizId,
              purpose: FirestoreService.purposeWorkerDirectory);
        } catch (e) {
          debugPrint('⚠️ [초대만 있는 날] 초대받은 사람 조회 실패: $e');
        }
      }

      if (!mounted || _selectedBusinessId != bizId) return;
      setState(() {
        _pendingApps = pending;
        _confirmedApps = confirmed;
        _userMap = userMap;
        _contractStatusMap = contractMap;
        _weeklyWorkCountMap = weeklyMap;
        _dayStaffingRows = staffingRows;
        _dayInvitations = invitations;
        _hasWorkedMap = {}; // [BUG-CANCEL-01] 확정자 없으면 초기화
        _noShowApplicationIds = {}; // [R5.1]
        _isLoading = false;
        _rebuildGroups();
      });
    } catch (e) {
      debugPrint('❌ 지원명단 로드 실패: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _pendingApps = [];
        _confirmedApps = [];
        _cachedGroups = [];
        _userMap = {};
        _contractStatusMap = const ContractStatusBatch();
        _idCardStatusMap = {};
        _workDetailCapacityMap = {};
        _capacityUnknown = true; // [R8-P7.3] 전체 로드 실패도 정원을 모르는 상태다
        _dayStaffingRows = null; // 전체 로드 실패 — 충원 영역도 UNKNOWN
        _dayInvitations = null;
        _weeklyWorkCountMap = {};
        _hasWorkedMap = {}; // [BUG-CANCEL-01] 로드 실패 시도 초기화
        _noShowApplicationIds = {}; // [R5.1]
      });
      ToastHelper.showError('데이터를 불러오지 못했습니다. 다시 시도해주세요.');
    }
  }

  Future<Map<String, int>> _loadWeeklyCount(String bizId) async {
    try {
      // [R7-P1-2 DEVICE.1G] 주간 창과 세는 규칙을 canonical 한 곳에서 가져온다.
      //
      //   여기는 `date.subtract(Duration(days: date.weekday - 1))` 로 직접
      //   계산했다. `date.weekday` 는 기기 달력 성분이고 KST 정규화가 없다.
      //   공고탭 인력 현황은 `WeekHelper` 를 쓰므로, 같은 사람·같은 날짜에
      //   대해 두 화면이 다른 주를 봤다(DEV 실측: 주1회 vs 주0회).
      //
      //   세는 것도 문서 수가 아니라 **근무한 날** 수다 — 같은 사람의 9/20
      //   에 출근 문서가 4건 있었다.
      final result = await _reads.weeklyAttendance(
        businessId: bizId,
        weekStart: WeekHelper.weekStart(widget.date),
        weekEnd: WeekHelper.weekEnd(widget.date),
      );
      return WeekHelper.workedDayCounts(result);
    } catch (e) {
      debugPrint('⚠️ _loadWeeklyCount 조회 실패 (빈 맵 반환): $e');
      return {};
    }
  }

  /// 슬롯 문서의 workDetails별 requiredCount 맵 반환 (업무 단위 정원 표시용)
  ///
  ///   [R8-P7.3] 실패하면 빈 맵을 돌려주되 [_capacityUnknown] 을 세운다.
  ///   지원자 명단은 유효하므로 다이얼로그 전체를 오류로 만들지 않는다 —
  ///   대신 충원/정원 영역만 UNKNOWN 으로 내린다. 예전에는 실패가 빈 맵이 되고
  ///   소비부가 `?? 0` 으로 읽어 "정원 0"이라고 단정했다.
  Future<Map<String, int>> _loadWorkDetailCapacities(List<ApplicationModel> allApps) async {
    try {
      return await _loadWorkDetailCapacitiesOrThrow(allApps);
    } catch (e) {
      debugPrint('⚠️ 업무별 정원 조회 실패 (충원 영역 UNKNOWN): $e');
      _capacityUnknown = true;
      return {};
    }
  }

  Future<Map<String, int>> _loadWorkDetailCapacitiesOrThrow(
      List<ApplicationModel> allApps) async {
    final toSlotMap = <String, String>{};
    for (final app in allApps) {
      if (app.toId != null && app.slotId != null && !toSlotMap.containsKey(app.toId!)) {
        toSlotMap[app.toId!] = app.slotId!;
      }
    }

    if (toSlotMap.isEmpty) {
      // 장기TO 폴백: TO 문서의 workDetails에서 개별 requiredCount
      final toIds = allApps.where((a) => a.toId != null).map((a) => a.toId!).toSet().toList();
      if (toIds.isEmpty) return {};
      final tos = await Future.wait(toIds.map((id) => _reads.to(id)));
      final res = <String, int>{};
      for (var i = 0; i < toIds.length; i++) {
        final to = tos[i];
        if (to == null) continue;
        for (final wd in to.workDetails) {
          final key = wd.id.isNotEmpty ? wd.id : '${wd.workType}_${wd.startTime}_${wd.endTime}';
          res[key] = wd.requiredCount;
        }
      }
      return res;
    }

    final result = <String, int>{};
    await Future.wait(toSlotMap.entries.map((e) async {
      final caps = await _reads.slotWorkDetailCapacities(e.key, e.value);
      _slotWorkDetailIds['${e.key}|${e.value}'] = caps.keys.toSet();
      result.addAll(caps);
    }));
    return result;
  }

  /// [4J.0C] 대기 중 지원서의 TO 모델을 _toCache에 선제 로드
  /// 목적: canApprovePending UI gate (승인 버튼 show/hide, _batchApprove guard)
  /// - 캐시 미적중 시 낙관적 허용 처리 (CF가 최종 차단)
  Future<void> _fetchToCacheForPending(List<ApplicationModel> pending) async {
    final toIds = pending
        .map((a) => a.toId)
        .whereType<String>()
        .toSet()
        .toList();
    if (toIds.isEmpty) return;
    await Future.wait(toIds.map((id) async {
      final to = await _reads.to(id);
      if (to != null) _toCache[id] = to;
    }));
  }

  // ── Grouping ───────────────────────────────────────────────────────────────

  void _rebuildGroups() => _cachedGroups = _buildGroups();

  List<_GroupData> _buildGroups() {
    final Map<String, _GroupData> groups = {};

    void addApp(ApplicationModel app, bool isPending) {
      // [8.1E.4] wdId 우선 그룹키 — 동일 wdId 앱은 같은 그룹으로 집계
      final wKey = app.wdId?.isNotEmpty == true
          ? app.wdId!
          : (app.workDetailId?.isNotEmpty == true
              ? app.workDetailId!
              : '${app.selectedWorkType}_${app.startTime}_${app.endTime}');
      final key = '${app.toId ?? app.toTitle}_$wKey';
      // [R7-PRE0] capacity 맵과 같은 canonical key 순서로 찾는다.
      //
      //   맵은 wdId 로 만들어진다(to_firestore.getSlotWorkDetailCapacities).
      //   여기서 workDetailId 를 먼저 보면 둘이 다른 값을 가리켜 조회가
      //   빗나가고, `?? 0` 때문에 "정원 0 = 더 뽑을 필요 없음"이 되어
      //   충원 버튼이 사라진다. 위 그룹키(wKey)도 이미 wdId 를 먼저 본다.
      //
      //   workDetailId·composite 폴백은 남긴다 — legacy 지원서 호환.
      final compositeKey = app.wdId?.isNotEmpty == true
          ? app.wdId!
          : (app.workDetailId?.isNotEmpty == true
              ? app.workDetailId!
              : '${app.selectedWorkType}_${app.startTime}_${app.endTime}');
      groups.putIfAbsent(
        key,
        () => _GroupData(
          toId: app.toId,
          toTitle: app.toTitle,
          workType: app.selectedWorkType,
          startTime: app.startTime,
          endTime: app.endTime,
          isLongTerm: app.isLongTermApplication,
          wdId: app.wdId,
          workDetailId: app.workDetailId,
          requiredCount: _workDetailCapacityMap[compositeKey] ?? 0,
          // [R8-P7.3] 정원을 못 읽었으면 0 이 아니라 "모른다"로 전달한다.
          requiredCountKnown: !_capacityUnknown,
        ),
      );
      groups[key]!.slotId ??= app.slotId;
      if (isPending) {
        groups[key]!.pendingApps.add(app);
      } else {
        groups[key]!.confirmedApps.add(app);
        // [R2.2.1] 이 확정이 초대에서 왔다면 초대 현황에도 결과로 남는다.
        //   추가 조회 없음 — 확정 명단이 이미 invitedAt을 싣고 온다.
        if (app.invitedAt != null) groups[key]!.acceptedInvites.add(app);
      }
    }

    for (final app in _pendingApps) {
      addApp(app, true);
    }
    for (final app in _confirmedApps) {
      addApp(app, false);
    }

    // [SYSTEM-INTEGRATION-R2.2] 초대를 같은 모집 단위(work instance)에 붙인다.
    //
    //   사람 단위로 합치지 않는다. 같은 근로자가 9/21과 9/22에 각각 초대받을 수
    //   있고, 한쪽을 거절했다고 다른 쪽까지 거절로 보이면 안 된다.
    //   묶는 단위는 지원서와 같은 `toId + wdId`다.
    void addInvite(ApplicationModel app) {
      final wKey = app.wdId?.isNotEmpty == true
          ? app.wdId!
          : (app.workDetailId?.isNotEmpty == true
              ? app.workDetailId!
              : '${app.selectedWorkType}_${app.startTime}_${app.endTime}');
      final key = '${app.toId ?? app.toTitle}_$wKey';
      final g = groups.putIfAbsent(
        key,
        () => _GroupData(
          toId: app.toId,
          toTitle: app.toTitle,
          workType: app.selectedWorkType,
          startTime: app.startTime,
          endTime: app.endTime,
          isLongTerm: app.isLongTermApplication,
          wdId: app.wdId,
          workDetailId: app.workDetailId,
          slotId: app.slotId,
        ),
      );
      g.slotId ??= app.slotId;
      if (app.status == AppStatus.invited) {
        g.invitedApps.add(app);
      } else {
        g.closedInvites.add(app);
      }
    }

    for (final app in _dayInvitations ?? const <ApplicationModel>[]) {
      addInvite(app);
    }

    // [SYSTEM-INTEGRATION-R2] slot canonical 모집 단위로 그룹을 보강한다.
    //
    //   위 루프는 지원서만 본다. 그래서 `필요 3 · 지원 0 · 확정 0`인 모집 단위는
    //   그룹이 생기지 않고, Home이 `3명 부족 ›`으로 보낸 화면이 비어 버린다.
    //   부족은 slot capacity에 속한 사실이므로 여기서 slot row를 그대로 세운다.
    //
    //   이미 지원서로 만들어진 그룹에는 requiredCount·slotId만 canonical 값으로
    //   덮는다 — 사람 목록은 지원서가 진실이고 정원은 slot이 진실이다.
    for (final row in _dayStaffingRows ?? const <DayStaffingRow>[]) {
      final key = '${row.toId}_${row.wdId}';
      final existing = groups[key];
      if (existing != null) {
        existing.requiredCount = row.requiredCount;
        // [R7-P1-PRODUCT] 지원서로 먼저 만들어진 그룹은 장기 여부를
        //   지원서에서 유도했다. canonical row가 왔으면 그쪽이 진실이다.
        existing.isLongTerm = row.isLongTerm;
        existing.workEndDate = row.workEndDate;
        existing.workDays = row.workDays;
        // [R8-P7.3] 정원은 slot 이 진실이다. 앞선 capacity 조회가 실패했더라도
        //   여기서 canonical 값을 받았으면 다시 "안다"가 된다.
        existing.requiredCountKnown = true;
        existing.slotId ??= row.slotId;
        // [R2.2.1] 확정 수도 slot이 진실이다 — 초대가 지금 수락될 수 있는지는
        //   근로자 화면과 같은 canonical 값으로 판정해야 한다.
        existing.canonicalConfirmed = row.confirmedCount;
        existing.canonicalClosed = row.isClosed;
        existing.canonicalInviteEnded = row.inviteEnded;
        existing.canonicalInviteOpen = row.inviteOpen;
        continue;
      }
      // [R2 FINAL] 종료된 모집 단위로는 **새 그룹을 세우지 않는다.**
      //   이 루프의 목적은 `지원자 0명이어도 채울 수 있는 자리`를 보여주는
      //   것이다. 종료된 단위는 채울 수 없으므로 보여 줄 이유가 없다.
      //   이미 지원·초대가 있어 그룹이 선 경우에는 위에서 종료 사실을 실어
      //   주므로, 그 초대가 왜 수락되지 않는지 관리자가 알 수 있다.
      //   [R7-P1-2 DEVICE.1I] 술어를 이름으로 둔다 — 머리말 count 가 같은
      //   규칙을 쓸 수 있어야 한다(`DayStaffingRow.seedsGroup`).
      if (!row.seedsGroup) continue;
      groups[key] = _GroupData(
        toId: row.toId,
        toTitle: row.toTitle,
        workType: row.workType,
        startTime: row.startTime,
        endTime: row.endTime,
        // [R7-P1-PRODUCT] `false` 고정이었다. 서버가 장기 row를 보내기
        //   시작하면 그 그룹이 단기로 표시되고, 초대 경로도 단기의 것을
        //   쓰게 된다 — 장기에는 슬롯이 없으므로 그 초대는 서지 못한다.
        isLongTerm: row.isLongTerm,
        wdId: row.wdId,
        requiredCount: row.requiredCount,
        slotId: row.slotId.isEmpty ? null : row.slotId,
      )
        ..canonicalConfirmed = row.confirmedCount
        ..canonicalClosed = row.isClosed
        ..canonicalInviteEnded = row.inviteEnded
        ..canonicalInviteOpen = row.inviteOpen
        ..workEndDate = row.workEndDate
        ..workDays = row.workDays;
    }

    int timeToMinutes(String t) {
      final parts = t.split(':');
      if (parts.length != 2) return 0;
      return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    }

    return groups.values.toList()
      ..sort((a, b) {
        final t = a.toTitle.compareTo(b.toTitle);
        if (t != 0) return t;
        final s = timeToMinutes(a.startTime).compareTo(timeToMinutes(b.startTime));
        if (s != 0) return s;
        return timeToMinutes(a.endTime).compareTo(timeToMinutes(b.endTime));
      });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // [POSTING-V2-03B.1] 대상 사업장 권한 변경에 반응한다.
    //   _canForSelectedBiz는 listen:false로 평가되므로(이벤트 핸들러 겸용)
    //   rebuild 구독은 여기 한 줄로만 건다.
    context.watch<UserProvider>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _hasChanges);
      },
      child: AppModalShell(
        children: [
          _buildHeader(context),
          // [R7-P1-2 DEVICE.1I] `Expanded` → `Flexible`.
          //
          //   DEVICE.1H 가 업무 명단에서 고친 것과 **같은 결함**이고, 이 진입에는
          //   적용되지 않아 있었다. `AppModalShell` 은
          //   `Column(mainAxisSize: min)` 이고 그 문서도 `Flexible(child: body)`
          //   를 규정한다. `Expanded` 는 남은 공간을 강제로 채우므로 높이가 항상
          //   화면의 95% 가 된다 — 9/30 처럼 그룹이 둘뿐인 날 아래쪽이 크게
          //   비어 있었다(실기기 캡처).
          //
          //   많은 행에서는 그대로 상한까지 자라고 내부 스크롤로 닿는다.
          Flexible(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: LoadingWidget(message: '인력 현황 불러오는 중...'),
                  )
                : _buildStatsAndBody(context),
          ),
          if (!_isLoading && _selectedIds.isNotEmpty)
            _buildBatchActionBar(context),
          _buildBottomBar(context),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  /// [R7-P1-2 DEVICE.1H §3] 이 화면이 **무엇을 조회한 범위**인지 머리말이 말한다.
  ///
  ///   공고탭의 인력 현황은 제목에 업무명이 있어 대상이 하나임이 드러난다.
  ///   이 화면은 날짜만 적혀 있어서 「1 공고」인지 「그 날짜의 여러 공고」인지
  ///   알 수 없었다 — 같은 제목·같은 날짜로 두 화면이 다른 모집단을 말했다.
  ///
  ///   세는 기준은 canonical identity 다. 업무 **이름의 종류 수**가 아니라
  ///   `wdId`(없으면 composite) 단위의 업무 건수를 센다 — 같은 업무명이 시간대
  ///   별로 두 건이면 2다.
  ///
  ///   **완전한 결과일 때만 적는다.** `_dayStaffingRows == null` 은 조회 실패
  ///   (UNKNOWN)이므로 `공고 0개` 같은 수를 만들어 내지 않고 날짜만 남긴다.
  ///   `전체` 라는 말은 쓰지 않는다 — 사업장 전체인지 진입 시 좁혀진 범위인지
  ///   이 화면이 단정할 수 없다.
  ///
  /// [R7-P1-2 DEVICE.1I] **본문과 같은 projection 을 센다.**
  ///
  ///   DEVICE.1H 는 `_dayStaffingRows`(filter 이전 raw rows)를 셌다. 그런데
  ///   `_buildGroups` 는 `row.isClosed` 인 모집 단위로 **새 그룹을 세우지
  ///   않는다**(채울 수 없으므로). 그래서 종료된 단위가 섞인 날에는 머리말이
  ///   `공고 8개 · 업무 8개` 라고 하면서 본문에는 2개만 보였다 — 실기기
  ///   9/28·9/30 캡처가 그것이다.
  ///
  ///   제목·머리말 count·요약·본문은 같은 범위를 말해야 한다. 그래서
  ///   `_cachedGroups`(본문이 그리는 바로 그 목록)에서 센다. 새 query 를
  ///   만들지 않고 기존 filtered projection 을 그대로 쓴다.
  ///
  ///   업무 단위는 그룹 하나 = `toId + wdId` 하나다(그룹 키가 그렇게 만들어
  ///   진다). 공고 수는 그 그룹들의 distinct `toId` 다.
  String _headerScopeLabel() {
    final groups = _cachedGroups;
    final toIds = <String>{};
    for (final g in groups) {
      final id = g.toId;
      if (id != null && id.isNotEmpty) toIds.add(id);
    }
    return DayStaffingRow.scopeLabel(
      dateLabel: FormatHelper.formatDateLong(widget.date),
      rowsUnknown: _dayStaffingRows == null,
      postingIds: toIds,
      workUnitCount: groups.length,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return AppModalHeader(
      // [R7-P1-7 §15] `지원명단` → `인력 현황`.
      //   WorkApplicantsDialog는 같은 역할을 `지원자 관리`라고 불렀다. 같은 일을
      //   하는 두 화면이 서로 다른 이름을 갖고 있었고, 어느 쪽도 이 화면이
      //   실제로 하는 일을 담지 못했다 — 여기서는 지원만 보는 게 아니라
      //   확정·초대·계약·서류 후속까지 처리한다.
      title: '인력 현황',
      // [COMMON-TEXT-LAYOUT.28] 좁은 폭에서 다음 줄이 '· 업무 3개' 로 시작했다 — 구분점을 앞 조각에 붙인다.
      // [DU1 후속38 B2-L] joinParts 는 조각('2026년 9월 29일 (화)')을 한 덩어리로 묶어, 칸보다 길면 Flutter 가 '29|일' 로
      //   강제로 끊었다(320·2.0). phrases 는 구분점을 앞 조각에 붙이는 규칙은 같고, 조각 안 **공백에서만** 줄을 바꾼다.
      subtitle: TextLayout.phrases(_headerScopeLabel()),
      onClose: () => Navigator.pop(context, _hasChanges),
      // [AH-V2-04B] 선택지 기준으로 판단한다. businesses(이름 조회용 전체 목록)로
      //   판단하면 실제 옵션이 1개여도 selector가 떴다.
      //   (Home 부족 진입·노쇼 좌석반납 진입이 businessIds를 좁혀서 넘긴다)
      trailing: widget.businessIds.length > 1
          ? AppSelectField<String>(
              value: _selectedBusinessId,
              hintText: '사업장을 선택하세요',
              sheetTitle: '사업장 선택',
              items: widget.businessIds,
              labelOf: (id) => _bizName(id),
              prefixIcon: Icons.business,
              // [DU520] 긴 사업장 이름이 '강남구 테헤…'로 잘렸다(DU515 r3 B-MULTI) — 이 칸만 낱말 단위로 줄을 넘겨 전부 보인다.
              wrapLabel: true,
              onChanged: (value) {
                if (value != null && value != _selectedBusinessId) {
                  setState(() => _selectedBusinessId = value);
                  SharedPreferences.getInstance().then(
                    (prefs) => prefs.setString('alfit_last_business_id', value),
                  );
                  _load();
                }
              },
            )
          : null,
    );
  }

  // ── Stats Strip ────────────────────────────────────────────────────────────

  Widget _buildStatsStrip(BuildContext context) {
    // [UX-D-02] 총 부족 = workDetail별 max(required_i - confirmed_i, 0) 합산
    // aggregate 공식(Σrequired - Σconfirmed)은 과충원 그룹이 다른 그룹 부족을 상쇄하므로 사용 금지
    // [R2.4] 계산식은 _GroupData.shortage 하나다 — 반납 좌석·모집 종료 포함.
    final totalShortage =
        _cachedGroups.fold<int>(0, (acc, g) => acc + g.shortage);
    // [R7-P1-6 §14] 부족은 **실패가 아니라 지금 처리 가능한 미완료**다.
    //   red를 쓰면 NO_SHOW·이체 실패 같은 실제 문제와 같은 무게가 되고,
    //   모집 초기의 정상 상태(아직 아무도 안 뽑음)가 사고처럼 보인다.
    //   red는 실제 문제에 남겨 둔다.
    final shortageColor =
        totalShortage > 0 ? AppColors.warningDark : AppColors.grey500;
    final showBatchToggle = _pendingApps.length >= 2 || _isBatchMode;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.grey200)),
      ),
      // [DU1 후속38 B2-L] 320·2.0 에서 일괄선택 버튼이 같은 줄 폭을 가져가 세 통계 칸이 좁아졌고, '3|0|건'·'지|원' 처럼
      //   글자 단위로 세로로 쌓였다(고정 영역이 커져 목록 표시 높이도 줄었다). **글자 배율로 나눈 폭이 좁을 때만**
      //   일괄선택을 통계 아래 오른쪽 줄로 내린다 — 통계 셋은 전폭을 쓴다. 넓은 폭(392·1.0 등)은 지금 한 줄 그대로.
      child: LayoutBuilder(builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = showBatchToggle && constraints.maxWidth / scale < 260;
        final stats = <Widget>[
          // 부족 = 필요한 자리 수 → `명`
          _statCell(context, '부족', totalShortage, shortageColor),
          _statDivider(context),
          // 지원·확정 = 관계 건수 → `건` (같은 사람이 두 공고에 걸칠 수 있다)
          // [UI-SCREEN-CONSISTENCY.1] 지원·확정 수는 사실이다 — 의미색은 처리할 일(부족)에만 남긴다.
          _statCell(context, '지원', _pendingApps.length,
              _pendingApps.isEmpty ? AppColors.grey500 : AppColors.textPrimary,
              unit: '건'),
          _statDivider(context),
          _statCell(context, '확정', _confirmedApps.length,
              _confirmedApps.isEmpty ? AppColors.grey500 : AppColors.textPrimary,
              unit: '건'),
        ];
        // [R7-P1-PRODUCT §17] 일괄선택에는 아무 게이트도 없었다.
        //   이 버튼의 bulk 대상은 PENDING 지원자다(일괄 확정·거절).
        //   1명이면 그 사람 카드의 action이 이미 같은 일을 한다.
        //   이미 들어가 있는 동안에는 계속 보여 준다 — `취소`가 여기 있다.
        final toggle = showBatchToggle ? Material(
            color: _isBatchMode
                ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                : AppColors.grey100,
            borderRadius: BorderRadius.circular(
                ResponsiveHelper.spacing(context, 8)),
            child: InkWell(
              onTap: () {
                // BATCH-STRIP-01: 일괄 확정 진입 시 canManageTo 확인
                if (!_isBatchMode) {
                  if (!_canForSelectedBiz((p) => p.canManageTo)) {
                    ToastHelper.showWarning('일괄 확정 권한이 없습니다.');
                    return;
                  }
                }
                setState(() {
                  _isBatchMode = !_isBatchMode;
                  if (!_isBatchMode) {
                    _selectedIds.clear();
                  } else {
                    // 다른 모드와 상호 배제
                    _idCardSelectGroupKey = null;
                    _selectedIdCardUserIds.clear();
                    _contractBatchGroupKey = null;
                  }
                });
              },
              borderRadius: BorderRadius.circular(
                  ResponsiveHelper.spacing(context, 8)),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8),
                  vertical: ResponsiveHelper.spacing(context, 4),
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
          ) : null;
        if (toggle == null) return Row(children: stats);
        if (!stacked) return Row(children: [...stats, _statDivider(context), toggle]);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: stats),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Align(alignment: Alignment.centerRight, child: toggle),
          ],
        );
      }),
    );
  }

  /// [R7-P1-2 DEVICE.1H §3] 단위를 모집단에 맞춘다.
  ///
  ///   세 셀이 모두 `N명` 이었다. `부족` 은 필요한 **자리 수**라 `명` 이 맞지만
  ///   `지원`·`확정` 은 `_pendingApps`/`_confirmedApps`(= `List<ApplicationModel>`)
  ///   의 길이, 즉 **관계 건수**다. 이 화면은 그 날짜의 여러 공고를 함께 보므로
  ///   한 사람이 두 건을 가질 수 있고, 그때 `2명` 이라고 말하게 된다.
  ///
  ///   수치는 바꾸지 않는다(모집단 재정의 금지). 단위만 사실에 맞춘다.
  Widget _statCell(BuildContext context, String label, int count, Color color,
      {String unit = '명'}) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count$unit',
              style: ResponsiveHelper.smallStyle(context)
                  .copyWith(fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style:
                  ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
        ],
      ),
    );
  }

  Widget _statDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      color: AppColors.grey200,
      margin: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 8)),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  /// [DU524] 통계 줄 + 본문. 머리(제목 · 날짜 · 사업장 칸)와 하단을 빼고 남은 칸이 화면 높이의 45% 미만이면(320×640 · 2.0 · 사업장 둘:
  ///   남은 칸 약 203 = 32%, 그중 통계 86 을 빼면 목록이 한 줄 남짓) 통계 줄을 목록 스크롤의 첫 항목으로 옮겨 목록에 칸을 내준다.
  ///   그 밖(390×844 약 66% · 320×640 사업장 하나 약 61%)은 이전과 같은 배치(통계 고정 → 본문)다. 실패 · 빈 상태는 어느 쪽이든 통계 고정.
  ///   통계 값 · 글 · 색 · 크기 · 순서는 같은 위젯 그대로다.
  Widget _buildStatsAndBody(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final stats = _buildStatsStrip(context);
      if (constraints.maxHeight < MediaQuery.sizeOf(context).height * 0.45) {
        final body = _buildBody(context, statsFirst: stats);
        if (body is CustomScrollView) return body;
        return Column(children: [stats, Expanded(child: body)]);
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [stats, Flexible(child: _buildBody(context))],
      );
    });
  }

  Widget _buildBody(BuildContext context, {Widget? statsFirst}) {
    final rows = _dayStaffingRows;
    // [R2.2] 초대만 있는 날도 보여줄 것이 있다 — 관리자가 보낸 초대의 결과다.
    final hasApps = _pendingApps.isNotEmpty ||
        _confirmedApps.isNotEmpty ||
        (_dayInvitations?.isNotEmpty ?? false);

    // [SYSTEM-INTEGRATION-R2] 지원자가 없다고 해서 '할 일이 없다'가 아니다.
    //
    //   Home이 `3명 부족 ›`으로 보낸 화면이 여기서 `지원자 없음`으로 끝나면
    //   관리자는 부족을 보고 들어와 아무것도 하지 못한 채 되돌아간다.
    //   지원서가 0건이어도 모집 단위가 있으면 부족과 `인력 초대`를 보여준다.
    if (!hasApps) {
      if (rows == null) {
        // 조회 실패 — '충원할 것이 없다'로 바꾸지 않는다 (ERROR != ZERO).
        final retry = TextButton(
          onPressed: _load,
          child: const Text('다시 시도'),
        );
        // [DU517] 큰 글자(320×640 · 2.0)에서 안내 글이 본문 칸보다 길어 '다시 시도'가 203px 아래로 밀렸다(DU515 r3 B-FAIL).
        //   큰 글자일 때만 안내 글은 위 칸에서 스크롤하고 '다시 시도'는 그 아래에 고정한다 — 글 · 버튼 · 색은 그대로, 배치만.
        //   기본 글자 크기(배율 1.3 이하)는 이전 배치 그대로다.
        if (MediaQuery.textScalerOf(context).scale(1) > 1.3) {
          return Column(
            children: [
              const Expanded(
                child: AppEmptyState(
                  icon: Icons.error_outline,
                  iconColor: AppColors.error,
                  title: '인력 현황을 불러오지 못했어요',
                  subtitle: '지원자와 부족 인원을 확인할 수 없습니다.',
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                    bottom: ResponsiveHelper.spacing(context, 8)),
                child: retry,
              ),
            ],
          );
        }
        return Padding(
          padding: const EdgeInsets.all(32),
          child: AppEmptyState(
            icon: Icons.error_outline,
            iconColor: AppColors.error,
            title: '인력 현황을 불러오지 못했어요',
            subtitle: '지원자와 부족 인원을 확인할 수 없습니다.',
            action: retry,
          ),
        );
      }
      if (rows.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(32),
          child: AppEmptyState(
            icon: Icons.people_outline,
            title: '지원자 없음',
            subtitle: '이 날짜에 지원하거나 확정된 근무자가 없습니다.',
          ),
        );
      }
      // 모집 단위는 있는데 지원자가 없다 — 부족과 충원 CTA를 보여주는 경로.
    }
    return _buildListBody(context, statsFirst: statsFirst);
  }

  Widget _buildListBody(BuildContext context, {Widget? statsFirst}) {
    final groups = _cachedGroups;
    if (groups.isEmpty) {
      return const AppEmptyState(
        icon: Icons.people_outline,
        title: '지원자가 없습니다',
      );
    }

    // 공고별로 묶기 (순서 유지)
    final byTO = <String, List<_GroupData>>{};
    for (final g in groups) {
      byTO.putIfAbsent(g.toKey, () => []).add(g);
    }

    final toKeys = byTO.keys.toList();
    // [NOSHOW-CONTRACT-GUARD] 근태를 몰라 발행을 멈춘 행이 있으면 맨 위에 이유·재시도.
    final notice = _contractAttendanceSuppressed ? 1 : 0;
    if (statsFirst != null) {
      // [DU524] 통계 줄을 목록 첫 항목으로 — 통계는 여백 밖(창 폭 그대로), 묶음 목록은 아래 ListView 와 같은 여백 · 간격 · 항목.
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: statsFirst),
          SliverPadding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            sliver: SliverList.separated(
              itemCount: toKeys.length + notice,
              separatorBuilder: (_, __) =>
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              itemBuilder: (_, i) => i < notice
                  ? ContractAttendanceUnknownNotice(
                      onRetry: _retryContractAttendance,
                      retrying: _contractAttRetrying)
                  : _buildTOSection(context, byTO[toKeys[i - notice]]!),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      itemCount: toKeys.length + notice,
      separatorBuilder: (_, __) =>
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
      itemBuilder: (_, i) => i < notice
          ? ContractAttendanceUnknownNotice(
              onRetry: _retryContractAttendance,
              retrying: _contractAttRetrying)
          : _buildTOSection(context, byTO[toKeys[i - notice]]!),
    );
  }

  // ── TO Section (공고 헤더 + 업무 서브섹션들) ──────────────────────────────

  Widget _buildTOSection(BuildContext context, List<_GroupData> groups) {
    final first = groups.first;
    final totalPending = groups.fold(0, (s, g) => s + g.pendingApps.length);
    final totalConfirmed = groups.fold(0, (s, g) => s + g.confirmedApps.length);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 공고 헤더 ──
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            decoration: const BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 5),
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: first.isLongTerm
                        ? AppColors.longTermBg
                        : AppColors.shortTermBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: first.isLongTerm
                          ? AppColors.longTermDark.withValues(alpha: 0.3)
                          : AppColors.shortTermDark.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    first.isLongTerm ? '장기' : '단기',
                    style: ResponsiveHelper.tinyStyle(
                      context,
                      color: first.isLongTerm
                          ? AppColors.longTermDark
                          : AppColors.shortTermDark,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                // [DU1 후속38 B2-L] 320·2.0 에서 공고 제목이 '단…' 으로 말줄임돼 어느 공고인지 사라졌다(제목 말줄임 금지) —
                //   단어 단위로 줄바꿈한다. 오른쪽 통계 Wrap 은 그대로(좁으면 배지가 아래로).
                Expanded(
                  child: Text(
                    TextLayout.keepWords(first.toTitle.isNotEmpty ? first.toTitle : first.workType),
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                // 전체 통계 요약
                // [R7-P4.4E.6B] 이 요약이 줄어들 수 없어 제목과 함께 줄을
                //   넘쳤다(배율 2.0 55px, 지원 120·확정 48 표본 127px).
                //   지원·확정 수는 운영 판단의 근거이므로 감추지 않고
                //   좁아지면 배지를 아래로 내린다.
                // [DU523] 합계 배지는 업무가 둘 이상일 때만 나온다. 배지가 없을 때도 이 칸이 제목(Expanded)과 남은 폭을 반씩 나눠,
                //   제목 칸이 한 낱말보다 좁아져 '야간/상하/차'로 끊겼다(320×640 · 2.0 · DU517 B-MULTI) — 보일 배지가 없으면 칸을 두지 않는다.
                if (groups.length > 1 && (totalPending > 0 || totalConfirmed > 0))
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    runSpacing: ResponsiveHelper.spacing(context, 2),
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                    // [UI-SCREEN-CONSISTENCY.1] 업무가 하나면 이 합계는 바로 아래 업무 줄과 같은 숫자다.
                    //   같은 값을 두 번 강조하지 않는다 — 업무가 둘 이상(합계가 다를 때)만, 중립색으로.
                    if (totalPending > 0 && groups.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '지원 $totalPending',
                          style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.textSecondary)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    if (totalConfirmed > 0 && groups.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '확정 $totalConfirmed',
                          style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.textSecondary)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── 업무별 서브섹션 ──
          ...groups.asMap().entries.map((e) {
            final isLast = e.key == groups.length - 1;
            return _buildWorkSubSection(context, e.value,
                isLast: isLast, hasMultipleParts: groups.length > 1);
          }),
        ],
      ),
    );
  }

  // ── Work SubSection (업무별 서브섹션) ──────────────────────────────────────

  Widget _buildWorkSubSection(BuildContext context, _GroupData g,
      {required bool isLast, bool hasMultipleParts = false}) {
    final pendingIds = g.pendingApps.map((a) => a.id).toList();
    final allSelected = pendingIds.isNotEmpty &&
        pendingIds.every((id) => _selectedIds.contains(id));
    final someSelected = pendingIds.any((id) => _selectedIds.contains(id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 업무 서브헤더 ──
        GestureDetector(
          onTap: (!_isBatchMode || pendingIds.isEmpty)
              ? null
              : () => setState(() {
                    if (allSelected) {
                      _selectedIds.removeAll(pendingIds);
                    } else {
                      _selectedIds.addAll(pendingIds);
                    }
                  }),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            // [UI-SCREEN-CONSISTENCY.1] 회색 바탕이 이미 업무 줄을 구획한다 — 파란 세로선은 같은 일을 두 번 했다.
            decoration: const BoxDecoration(color: AppColors.grey100),
            child: Row(
              children: [
                if (_isBatchMode && pendingIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppCheckbox(
                      value: allSelected || someSelected,
                      activeColor: someSelected && !allSelected
                          ? AppColors.grey400
                          : null,
                    ),
                  ),
                // 업무명 + 시간
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.workType,
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      // [COMMON-TEXT-LAYOUT.28] 시간 범위 — 줄을 바꿔야 하면 '~' 뒤에서만('00:00 ~' / '23:30'). 자르지 않는다.
                      Text(
                        TextLayout.range(g.startTime, g.endTime),
                        semanticsLabel: '${g.startTime} ~ ${g.endTime}',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey500),
                      ),
                    ],
                  ),
                ),
                // 업무별 통계 배지
                // [R7-P1-2 DEVICE.1H.1] 고정 폭이라 대기 인원이 있는 묶음의
                //   머리줄이 320dp·배율 2.0 에서 6px 넘쳤다. 수치를 지우지 않고
                //   남은 폭 안으로 접는다.
                Flexible(child: _buildGroupStats(context, g)),
              ],
            ),
          ),
        ),

        // ── 대기 중 섹션 ──
        // [R4] Hierarchy: 이미 지원한 대기자를 먼저 검토 → outbound invite는 그 아래
        if (g.pendingApps.isNotEmpty) ...[
          // [CROSS-DOMAIN-R5.3B] 지원서 건수다. 다른 업무를 제안받은 사람은
          //   A(PENDING)와 B(INVITED)로 두 줄에 나타나므로 `명`이 아니다.
          _sectionDivider(
              context, '지원 (${g.pendingApps.length}건)', AppColors.warning),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8)),
            child: Column(
              children: g.pendingApps
                  .asMap()
                  .entries
                  .map((e) => _buildApplicantCard(context, e.value,
                      isPending: true, index: e.key + 1))
                  .toList(),
            ),
          ),
        ],

        // ── [SYSTEM-INTEGRATION-R2.2] 초대 현황 — 지원 섹션 다음, 초대 CTA 앞 ──
        //   보낸 초대가 어떻게 됐는지 먼저 보이고, 그래도 부족하면 더 보낸다.
        _buildInviteSection(context, g),

        // ── [Phase 8.1B.3 / R4] 인력 초대 버튼 — pending 섹션 이후 표시 ──
        // pending 먼저 처리 후 여전히 부족할 때 outbound invite CTA 노출
        // [R5.1] 좌석 반납된 확정자는 정원 계산에서 제외
        // [R2.2.1 CORRECTION] capacity를 **알고 있고 자리가 남은** 경우에만 띄운다.
        //
        //   `!= true`로 두면 UNKNOWN도 통과한다. 인력 현황을 읽지 못한 상태에서
        //   `인력 초대 (N명 부족)`을 띄우는 것은 확인하지 못한 부족을 확인한 것처럼
        //   말하는 것이고, 보내도 수락될 수 없는 초대를 낳을 수 있다.
        //   UNKNOWN일 때는 CTA 대신 `_buildCapacityUnknownNotice`가 선다.
        //
        // [R7-P1R §14] 장기도 여기서 초대할 수 있다.
        //
        //   직전까지는 막아 두었다. 이 화면이 쓰는 contextual 경로가
        //   workEndDate·workDays를 싣지 못해 장기 공고에 하루짜리 지원서를
        //   만들었기 때문이다. 이제 그 두 값을 canonical row가 실어 오고
        //   contextual 생성자가 그대로 전달한다 — 일반 모드(⋮ 메뉴)와
        //   같은 키, 같은 의미다.
        //
        //   그래도 약속 범위를 **모르면** 세우지 않는다. 장기인데
        //   workEndDate가 비어 있으면 하루짜리가 만들어지던 그 상태와
        //   같으므로, 그때는 CTA 대신 다른 경로를 안내한다.
        // [INVITE-TERMINAL] 공개 지원은 자동 마감됐지만 근무 시작 전이라 **인력 초대는
        //   가능한** 단위. 두 행동이 다르다는 것을 말하고 초대만 연다(공개 지원·
        //   대기자 확정을 다시 열지 않는다). 수동 마감·사업장 비활성은 inviteEnded 라
        //   여기 오지 않는다. 장기는 이 화면에서 열지 않는다.
        if (g.toId != null && g.requiredCount > 0 && !g.isLongTerm &&
            g.slotId != null && g.privateInviteShortage > 0)
          Builder(builder: (ctx) {
            if (!_canForSelectedBiz((p) => p.canManageTo)) {
              return const SizedBox.shrink();
            }
            return _buildPrivateInviteButton(g, g.slotId!);
          }),

        if (g.toId != null && g.requiredCount > 0 &&
            g.capacityState == InviteCapacityState.available &&
            g.shortage > 0)
          Builder(builder: (ctx) {
            if (!_canForSelectedBiz((p) => p.canManageTo)) {
              return const SizedBox.shrink();
            }
            if (g.isLongTerm) {
              // 약속 범위를 모르면 초대하지 않는다 — 하루짜리가 만들어진다.
              if (g.workEndDate == null) return _buildLongTermInviteHint(ctx);
              return _buildInviteButton(g, null);
            }
            // [R2] slotId는 그룹 자신이 안다. 이전에는 지원서에서 유도해
            //   지원자가 0명인 모집 단위에서 null이 되고 CTA가 사라졌다 —
            //   충원이 가장 필요한 상태에서 충원 수단이 없어지는 경로였다.
            final slotId = g.slotId;
            if (slotId == null) return const SizedBox.shrink();
            return _buildInviteButton(g, slotId);
          }),

        // [R2.2.1 CORRECTION] capacity UNKNOWN — 없는 것처럼 지나가지 않는다.
        //   충원 CTA를 내린 이유를 말해 준다. `부족 0`이라서가 아니라
        //   **읽지 못해서**다 (ERROR != ZERO).
        if (g.toId != null && (g.isLongTerm || g.slotId != null) &&
            g.isCapacityUnknown && _dayStaffingRows == null &&
            _canForSelectedBiz((p) => p.canManageTo))
          _buildCapacityUnknownNotice(context),

        // ── 확정 섹션 ──
        if (g.confirmedApps.isNotEmpty) ...[
          _sectionDivider(
              context, '확정 (${g.confirmedApps.length}명)', AppColors.success),
          Builder(builder: (ctx) {
            final requestableCount = g.confirmedApps.where((app) {
              final user = _userMap[app.uid];
              if (user == null) return false;
              return IdCardHelper.isRequestable(
                  _idCardStatusMap[user.uid] ?? 'none');
            }).length;
            // [R7-P1-5 §13] 1명이면 bulk UI를 세우지 않는다.
            //   한 사람에게 보낼 요청을 "일괄 처리" 패널로 감싸면, row에도
            //   같은 action이 있어 같은 일이 두 군데서 강하게 보인다.
            //   1명은 개인 카드의 action이 이미 처리한다.
            if (requestableCount < 2) return const SizedBox.shrink();
            return _buildIdCardRequestSection(ctx, g, requestableCount);
          }),
          Builder(builder: (ctx) {
            // [REISSUE-RECOVERY] 세는 것은 **계약서가 없다고 확인된** 확정자다.
            //   조회 실패를 여기 합산하면 가짜 업무가 생기고, 좌석을 반납한
            //   노쇼 건을 합산하면 보내면 안 되는 계약을 권하게 된다.
            //   [NOSHOW-CONTRACT-GUARD] 판정은 행과 같은 `_needsContractIssue` 하나다.
            final noContractCount = g.confirmedApps
                .where(_needsContractIssue)
                .length;
            // [R7-P1-5 §13] 1명이면 개인 카드 action만 — bulk 패널 없음.
            if (noContractCount < 2) return const SizedBox.shrink();
            return _buildContractBatchSection(ctx, g, noContractCount);
          }),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8)),
            child: Column(
              children: g.confirmedApps
                  .asMap()
                  .entries
                  .map((e) => _buildApplicantCard(context, e.value,
                      isPending: false,
                      isGroupIdCardMode: _idCardSelectGroupKey == g.groupKey,
                      index: e.key + 1,
                      hasMultipleParts: hasMultipleParts,
                      // [CROSS-SLICE-1] 종료된 모집 단위에는 대체충원을 권하지 않는다
                      isRecruitClosed: g.canonicalClosed))
                  .toList(),
            ),
          ),
        ],

        // ── 구분선 (마지막 업무 섹션 제외) ──
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.border,
            indent: ResponsiveHelper.spacing(context, 12),
            endIndent: ResponsiveHelper.spacing(context, 12),
          )
        else
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
      ],
    );
  }

  /// [UI-SCREEN-CONSISTENCY.1] 구획 제목은 중립색 한 가지다. 지원·확정·초대를 색 세로선과 의미색으로
  ///   나누면 한 화면에 주황·초록·파랑 막대가 겹쳤다 — 구분은 제목 글자가 한다.
  ///   [color] 는 호출부 호환을 위해 받지만 쓰지 않는다.
  Widget _sectionDivider(BuildContext context, String label, Color color) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 10),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 4),
      ),
      child: Row(
        children: [
          // [R7-P4.4E.6B] 구분선 라벨이 줄어들 수 없어 배율을 올리면 넘쳤다.
          Expanded(
            child: Text(label,
                style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.textSecondary)
                    .copyWith(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ── [Phase 8.1B.3] 인력 초대 버튼 + InviteMethodSheet 라우팅 ─────────────

  Widget _buildInviteButton(_GroupData g, String? slotId) {
    // [R2.4] 같은 계산식 — 이 버튼의 숫자와 열리는 시트의 숫자가 갈라지지 않는다.
    final shortage = g.shortage;
    // [UX-D-03] pendingCount >= shortage: 현재 대기자 풀로 이론적 부족 충족 가능
    // → 기존 지원자 처리가 운영 우선순위이므로 CTA를 tertiary 약화로 신호.
    // PENDING을 공식 shortage/capacity에서 차감하지 않음 — 시각 강도만 조정.
    // [CROSS-DOMAIN-R5.3B] 여기서만은 **사람 수**로 센다.
    //   "대기자 풀로 부족을 메울 수 있는가"는 사람에 대한 질문이고, 한 사람이
    //   A(PENDING)와 B(INVITED)로 두 건을 갖고 있어도 메울 수 있는 자리는 하나다.
    final isPendingSufficient =
        g.pendingApps.map((a) => a.uid).toSet().length >= shortage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: isPendingSufficient
          ? TextButton.icon(
              onPressed: () => _openInviteMethod(g, slotId),
              icon: const Icon(Icons.person_add_outlined, size: 16),
              label: Text('인력 초대 ($shortage명 부족)'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.grey600,
                alignment: Alignment.centerLeft,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            )
          : OutlinedButton.icon(
              onPressed: () => _openInviteMethod(g, slotId),
              icon: const Icon(Icons.person_add_outlined, size: 16),
              label: Text('인력 초대 ($shortage명 부족)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brand,
                side: const BorderSide(color: AppColors.brand),
                alignment: Alignment.centerLeft,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
    );
  }

  /// [INVITE-TERMINAL] 공개 지원 마감 후 비공개 인력 초대 — 같은 초대 시트를 연다.
  Widget _buildPrivateInviteButton(_GroupData g, String slotId) {
    final shortage = g.privateInviteShortage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '공개 지원은 마감됐어요 · 근무 시작 전까지 인력 초대는 가능해요',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => _openInviteMethod(g, slotId),
            icon: const Icon(Icons.person_add_outlined, size: 16),
            label: Text('인력 초대 ($shortage명 부족)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.brand,
              side: const BorderSide(color: AppColors.brand),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  /// [R7-P1-CORR] 같은 모집 단위의 초대 시트는 하나만 뜬다.
  Future<void> _openInviteMethod(_GroupData g, String? slotId) =>
      ActionGuard.runVoid(
        ActionGuard.keyOf('inviteMethod', [g.toId, slotId, g.wdId]),
        () => _openInviteMethodInner(g, slotId),
      );

  Future<void> _openInviteMethodInner(_GroupData g, String? slotId) async {
    if (!mounted) return;
    // [R2.4] 통계 스트립·초대 CTA와 **같은 값**을 쓴다.
    // [INVITE-TERMINAL] 공개 지원이 자동 마감된 단위의 비공개 초대 CTA 는
    //   공개 부족이 0 이라 그 CTA 가 보여 준 값(privateInviteShortage)을 넘긴다.
    final shortage = g.shortage > 0 ? g.shortage : g.privateInviteShortage;

    // 1. 인력 초대 방식 선택 시트 — State.context 사용 (mounted 보장)
    //
    // [R7-P1R §13] 장기는 방식 선택을 건너뛴다.
    //
    //   `근무 가능 인력` 시트(AvailableWorkersBottomSheet)와 그 뒤의
    //   callableGetAvailableWorkers는 slotId를 요구한다. 장기에는 슬롯이
    //   없고, 그 경로가 장기에서 올바른 결과를 주는지 확인되지 않았다.
    //   고를 수 없는 선택지를 보여 주고 눌렀을 때 실패시키지 않는다.
    //
    //   직접 초대는 이제 장기 약속 범위를 그대로 싣는다(§14).
    final String choice;
    if (slotId == null) {
      choice = 'direct';
    } else {
      final picked = await DialogHelper.showSheet<String>(
        context,
        builder: (ctx) => InviteMethodSheet(
          workType: g.workType,
          date: widget.date,
          startTime: g.startTime,
          endTime: g.endTime,
          shortage: shortage,
        ),
      );
      if (!mounted || picked == null) return;
      choice = picked;
    }
    if (!mounted) return;

    // 사업장명 취득
    final biz = widget.businesses.where((b) => b.id == _selectedBusinessId)
        .isNotEmpty
        ? widget.businesses.firstWhere((b) => b.id == _selectedBusinessId)
        : (widget.businesses.isNotEmpty ? widget.businesses.first : null);
    final businessName = biz?.name ?? '';

    if (choice == 'availability' && slotId != null) {
      // 2a. 근무 가능 인력 시트 — 슬롯이 있는 단기 전용이다.
      if (!mounted) return;
      await DialogHelper.showSheet<void>(
        context,
        isScrollControlled: true,
        builder: (ctx) => AvailableWorkersBottomSheet(
          toId: g.toId!,
          slotId: slotId,
          workDetailId: g.workDetailId,
          businessId: _selectedBusinessId ?? '',
          date: widget.date,
          workType: g.workType,
          startTime: g.startTime,
          endTime: g.endTime,
          requiredCount: g.requiredCount,
          // [R2.4 §19] 반납 좌석을 뺀 값 — 이 시트 헤더의 `확정 N · 부족 M`이
          //   방금 누른 `인력 초대 (M명 부족)` 버튼과 어긋나지 않게 한다.
          confirmedCount: g.seatedConfirmed,
          // [INVITE-REFRESH] 초대는 `대기`를 올리는 writer 다. 이 화면도,
          //   이 화면을 연 공고 카드도 그걸 모르고 있었다 — 아래 `_hasChanges`
          //   가 닫힐 때 카드의 `onChanged()` 와 Home 알림을 깨운다.
          onInviteSucceeded: () {
            if (!mounted) return;
            // [ISG2-REFRESH] 같은 공용 식을 쓴다.
            final outcome = inviteSheetOutcome(anySucceeded: true);
            if (outcome.propagate) _hasChanges = true;
            if (outcome.reload) _load();
          },
        ),
      );
    } else if (choice == 'direct') {
      // 2b. 직접 초대 다이얼로그 (contextual mode — 날짜·슬롯 재선택 없음)
      if (!mounted) return;
      // [INVITE-REFRESH] 다이얼로그는 닫힌 이유를 돌려준다 —
      //   그동안 `<void>` 로 받아 버리고 있었다.
      // [E1-AMBIGUOUS-INVITE] bool → InviteDialogResult(sent/canceled/unconfirmed).
      final invited = await showDialog<InviteDialogResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => InviteWorkerDialog.contextual(
          toId: g.toId!,
          businessId: _selectedBusinessId ?? '',
          businessName: businessName,
          date: widget.date,
          slotId: slotId,
          workType: g.workType,
          startTime: g.startTime,
          endTime: g.endTime,
          // [R7-P1R §14] 장기면 약속 범위를 함께 넘긴다 — 없으면 단기다.
          workEndDate: g.workEndDate,
          workDays: g.workDays.isEmpty ? null : g.workDays,
        ),
      );
      // [ISG2-REFRESH] 네 결과 판단은 `inviteDialogOutcome` 한 곳이 한다 —
      //   같은 규칙을 화면마다 다시 적지 않는다.
      if (!mounted) return;
      // [E1-AMBIGUOUS-INVITE] 불명확하게 닫혔으면 대상 지원서를 다시 읽어
      //   **저장이 확인된 경우에만** 상위로 전파한다.
      final resolved = await InviteSaveVerifier.resolve(
          inviteDialogOutcome(invited),
          businessId: _selectedBusinessId ?? '');
      if (!mounted) return;
      InviteSaveVerifier.announceClose(resolved.check);
      final outcome = resolved.outcome;
      if (outcome.propagate) _hasChanges = true;
      if (outcome.reload) await _load();
    }
  }

  // ── Applicant Card ─────────────────────────────────────────────────────────

  Widget _buildApplicantCard(BuildContext context, ApplicationModel app,
      {required bool isPending, bool isGroupIdCardMode = false, int index = 0,
      bool hasMultipleParts = false, bool isRecruitClosed = false}) {
    final user = _userMap[app.uid];
    final isSelected = _selectedIds.contains(app.id);
    final isStarred = isPending && _starredIds.contains(app.id);
    final idCardStatus = _idCardStatusMap[user?.uid ?? ''] ?? 'none';
    final canManageTo = _canForSelectedBiz((p) => p.canManageTo);
    final canManageContract = _canForSelectedBiz((p) => p.canManageContract);

    // [R7-P1-2 DEVICE.1H §4] 확정은 **완료된 사실**이다 — 낮은 강조.
    //
    //   카드 전체 초록 tint + 초록 테두리 + 초록 배지가 함께 서 있었다.
    //   D0 은 반복 강조 축소와 행당 강한 강조 제한을 규정하고, 완료 정보는
    //   낮은 강조로 둔다. 셋 다 같은 사실을 세 번 말하는 동안 정작 눌러야
    //   하는 것(계약서·서류 보완)이 묻힌다.
    //   배경 tint 를 내리고 테두리만 남긴다.
    //
    // [R7-P1-2 DEVICE.1H.1] 그 규칙을 `dayApplicantRowColors` 로 떼어 냈다 —
    //   실제로 그려서 확인할 수 있어야 하기 때문이다. 색 값은 여기서 넘기므로
    //   이 화면의 모양은 바뀌지 않는다.
    final rowColors = dayApplicantRowColors(
      isSelected: isSelected,
      isStarred: isStarred,
      isPending: isPending,
      // [UI-SCREEN-CONSISTENCY.1] 선택은 대표색이다 — 체크 표시(파랑)와 카드(주황)가 다른 색으로 같은 사실을 말했다.
      selectedBg: AppColors.brand.withValues(alpha: 0.06),
      selectedBorder: AppColors.brand,
      starredBg: Colors.white,
      starredBorder: AppColors.grey200,
      // [UI-SCREEN-CONSISTENCY.1] '확정' 구획 제목이 이미 말한다 — 행마다 초록 테두리로 반복하지 않는다.
      confirmedBorder: AppColors.grey200,
      plainBorder: AppColors.grey200,
    );

    return GestureDetector(
      onTap: () {
        if (isPending && _isBatchMode) {
          setState(() {
            if (isSelected) {
              _selectedIds.remove(app.id);
            } else {
              _selectedIds.add(app.id);
            }
          });
        } else if (!isPending && isGroupIdCardMode &&
            IdCardHelper.isRequestable(idCardStatus)) {
          _toggleIdCardSelection(user?.uid ?? '');
        } else {
          _showWorkerDetail(app, user, isPending: isPending);
        }
      },
      child: ApplicantRowSurface(
        background: rowColors.background,
        border: rowColors.border,
        borderWidth: rowColors.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: 체크박스/점 + 이름 + 나이성별 + 시간 + 별/리뷰 ──
            Row(
              children: [
                if (isPending)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isBatchMode
                        ? ResponsiveHelper.spacing(context, 26)
                        : 0,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    child: _isBatchMode
                        ? Padding(
                            padding: EdgeInsets.only(
                                right: ResponsiveHelper.spacing(context, 6)),
                            child: AppCheckbox(
                              value: isSelected,
                              onTap: () => setState(() {
                                if (isSelected) {
                                  _selectedIds.remove(app.id);
                                } else {
                                  _selectedIds.add(app.id);
                                }
                              }),
                            ),
                          )
                        : const SizedBox.shrink(),
                  )
                else if (isGroupIdCardMode)
                  Padding(
                    padding: EdgeInsets.only(
                        right: ResponsiveHelper.spacing(context, 6)),
                    child: IdCardHelper.isRequestable(idCardStatus)
                        ? AppCheckbox(
                            value: _selectedIdCardUserIds
                                .contains(user?.uid ?? ''),
                            onTap: () =>
                                _toggleIdCardSelection(user?.uid ?? ''),
                            activeColor: AppColors.brand,
                          )
                        : SizedBox(
                            width: ResponsiveHelper.spacing(context, 22)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '$index.',
                      style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.grey400)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          user?.name ?? '근무자',
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // [R7-PRE1A.1] 번호를 이름 옆 보조 문구로 — badge 가 아니다.
                      //   동명이인이 한 명단에 있으면 이름만으로는 어느 쪽을
                      //   고르는지 알 수 없다.
                      if (PersonLabel.secondary(
                              user?.personNo, _genderAge(user)).isNotEmpty) ...[
                        const SizedBox(width: 3),
                        Text(
                            PersonLabel.secondary(
                                user?.personNo, _genderAge(user)),
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey500)),
                      ],
                    ],
                  ),
                ),
                // [UI-SCREEN-CONSISTENCY.1] 윗줄은 이름·인력번호·별표만 — 지원 시각은 아래 보조 줄로 옮겼다.
                //   긴 이름 옆에서 번호·시각·별표가 한 줄을 다투며 이름이 잘리고 'P-006지원 6분 전' 으로 붙어 읽혔다.
                if (isPending)
                  GestureDetector(
                    onTap: () async {
                      final nowStarred = !_starredIds.contains(app.id);
                      setState(() {
                        if (nowStarred) { _starredIds.add(app.id); }
                        else { _starredIds.remove(app.id); }
                      });
                      try {
                        await _svc.updateApplicationFields(
                            app.id, {'isStarred': nowStarred});
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            if (nowStarred) { _starredIds.remove(app.id); }
                            else { _starredIds.add(app.id); }
                          });
                          ToastHelper.showError('별 표시 저장에 실패했습니다');
                        }
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        ResponsiveHelper.spacing(context, 5),
                        2,
                        0,
                        2,
                      ),
                      child: Icon(
                        isStarred
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: isStarred ? AppColors.amber : AppColors.grey300,
                      ),
                    ),
                  ),
              ],
            ),

            // ── Row 2: 보조 정보 (지원 시각·전화·노쇼·주간횟수·별점) ──
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // 줄을 넘길 수 있는 칸이다 — 큰 글자에서도 넘치지 않는다(R7-P1-2 DEVICE.1H.1 의 요구).
                Text(
                  _relationTimeAgo(app),
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.textTertiary),
                ),
                if (user?.effectivePhone != null && user!.effectivePhone!.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.phone_outlined,
                        size: 10, color: AppColors.grey400),
                    const SizedBox(width: 2),
                    Text(FormatHelper.formatPhone(user.effectivePhone!),
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey600)),
                  ]),
                if (user != null && user.recentNoShowCount > 0)
                  _buildNoShowBadge(context, user.recentNoShowCount),
                _weeklyCountBadge(context, app.uid),
                if (user != null && user.averageRating > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded,
                        size: 11, color: AppColors.amber),
                    const SizedBox(width: 2),
                    Text(
                      user.averageRating.toStringAsFixed(1),
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey700),
                    ),
                  ]),
              ],
            ),

            // ── Row 3: 배지 (리뷰·계약·신분증) — 정보 라인과 분리, Wrap 자동 줄바꿈 ──
            const SizedBox(height: 3),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // [R7-P1-4 §11] 리뷰 배지 제거.
                //   두 가지 문제가 겹쳐 있었다.
                //   (1) `_reviewWrittenMap`이 **확정자 전원**에 대해 만들어졌다.
                //       아직 근무 전인 사람, NO_SHOW만 있는 사람에게도
                //       `리뷰미작성`이 붙어 존재하지 않는 업무를 만들었다.
                //       canonical 자격은 실근무 + 마감이다
                //       (AttendanceModel.isActualFinalizedWork).
                //   (2) 자격을 맞춰도 이 카드에 있을 정보가 아니다. 여기서
                //       관리자가 판단하는 것은 충원이지 리뷰가 아니다.
                //       리뷰는 전용 화면(admin_review_list_screen)이 맡는다.
                _contractBadge(context, app, isPending: isPending),
                if (!isPending)
                  IdCardHelper.buildStatusBadge(context, idCardStatus),
              ],
            ),

            // ── Row 4: 액션 버튼 ──
            // [4J.0C] 거절: 항상 허용(PENDING 정리), 승인: canApprovePending만 허용 — WorkApplicants parity
            // _toCache에 TO가 없으면 true(낙관적 허용) — CF가 최종 gate
            if (isPending && !_isBatchMode && canManageTo) ...[
              const SizedBox(height: 8),
              // [R7-P1-2 DEVICE.1H.1] 고정 Row 라 320dp·배율 2.0 에서 버튼이
              //   행 밖으로 밀려 **눌리지 않았다**(세 개 중 하나가 사라졌다).
              //   버튼을 지우거나 글자 배율을 무효화하지 않는다 — 줄을 넘긴다.
              _actionRow(
                context,
                secondary: [
                  // [CROSS-DOMAIN-R5.3B] 다른 업무 제안 — WorkApplicants와 같은 행동.
                  //   후보 판정에 필요한 슬롯 WorkDetail은 이 화면이 들고 있지
                  //   않으므로 눌렀을 때 읽는다. 상시 listener를 붙이지 않는다.
                  // [UI-APPLICANTS-AND-INVITATIONS.2 §5] 이 슬롯에 다른 업무가 없다고 **확실하면** 숨긴다
                  //   (누르면 '제안할 수 있는 다른 업무가 없습니다' 만 나오던 버튼). 모르면 그대로 둔다.
                  if (app.slotId != null && app.toId != null && !_surelyNoOtherWork(app))
                    _actionButton(
                      context,
                      label: '다른 업무 제안',
                      role: _ActionRole.secondary,
                      onTap: () => _offerAlternativeWork(app, user),
                    ),
                  _actionButton(
                    context,
                    label: '거절',
                    role: _ActionRole.destructive,
                    onTap: () => _rejectApp(app),
                  ),
                ],
                primary: [
                  if (_toCache[app.toId]?.canApprovePending ?? true)
                    _actionButton(
                      context,
                      label: '확정',
                      role: _ActionRole.primary,
                      onTap: () => _approveApp(app),
                    ),
                ],
              ),
            ] else if (!isPending) ...[
              // [R5.1] 대체 충원 진행 중 배지 — staffingReleasedAt 설정 시 표시
              if (app.isStaffingReleased) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.warning, width: 1),
                    ),
                    child: Text(
                      '대체 충원 진행 중',
                      style: ResponsiveHelper.captionStyle(context).copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              // [BUG-CANCEL-01] 계약서 작성·확정취소·파트변경·대체충원 중 하나라도 표시할 때 Row 렌더링
              if (((_needsContractIssue(app) && canManageContract) ||
                  (_canCancelConfirmation(app) && canManageTo) ||
                  (app.toId != null && hasMultipleParts && canManageTo) ||
                  // [R5.1] NO_SHOW + 미반납 + 단기 + 권한 있을 때 버튼 표시
                  // [CROSS-SLICE-1] 종료된 날짜는 제외 — 반납해도 채울 수 없다
                  (_noShowApplicationIds.contains(app.id) && !app.isStaffingReleased &&
                      !app.isLongTermApplication && canManageTo &&
                      _isReplacementActionable && !isRecruitClosed))) ...[
                const SizedBox(height: 8),
                // [R7-P1-2 DEVICE.1H.1] 확정 행의 버튼 줄도 같은 이유로 넘쳤다.
                _actionRow(
                  context,
                  primary: [
                    // [R5.1] 대체 인력 충원 버튼 — NO_SHOW 확인 후 미반납 상태에서만 표시
                    if (_noShowApplicationIds.contains(app.id) &&
                        !app.isStaffingReleased &&
                        !app.isLongTermApplication &&
                        canManageTo &&
                        _isReplacementActionable &&
                        !isRecruitClosed) ...[
                      _actionButton(
                        context,
                        label: '대체 인력 충원',
                        role: _ActionRole.urgent,
                        onTap: () => _releaseNoshowSeat(app),
                      ),
                    ],
                    // 계약 미작성 시 개별 계약서 작성 버튼
                    if (_needsContractIssue(app) && canManageContract) ...[
                      _actionButton(
                        context,
                        label: '계약서 작성',
                        role: _ActionRole.primary,
                        onTap: () => _createContractForOne(app),
                      ),
                    ],
                  ],
                  secondary: [
                    // [BUG-CANCEL-01] 근무 완료·장기계약 시작 후에는 확정취소 버튼 숨김
                    if (_canCancelConfirmation(app) && canManageTo) ...[
                      _actionButton(
                        context,
                        label: '확정취소',
                        role: _ActionRole.destructive,
                        onTap: () => _cancelConfirmation(app),
                      ),
                    ],
                    // [CROSS-DOMAIN-R5.3A] '파트변경' CTA 제거.
                    //   관리자 혼자 확정된 약속을 덮어쓰는 경로였다. 업무를 옮기는
                    //   일은 제안이고 근로자가 수락해야 성립한다 — 그 구조(다른 업무
                    //   제안)가 준비되면 이 자리에 돌아온다. 서버도 함께 막혀 있다.
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// [UI-SCREEN-CONSISTENCY.1] 행 버튼은 역할로 모양을 정한다(색 이름이 아니라).
  ///   primary     — 그 행의 다음 일(확정·계약서 작성): 브랜드색 채움, 행마다 하나
  ///   secondary   — 부가 행동(다른 업무 제안): 테두리 없는 보조 글자, 같은 자리 유지
  ///   destructive — 되돌리기 어려운 행동(거절·확정취소): 테두리 없는 절제된 빨간 글자. 확인 창은 그대로
  ///   urgent      — 사고 대응(노쇼 대체 충원): 경고색 채움
  ///   높이·여백·모서리는 넷 다 같다. 예전에는 파랑·빨강·초록이 같은 무게로 행마다 반복됐다.
  /// [UI-SCREEN-CONSISTENCY.1 · 2차] 행 버튼 줄 — 보조 행동은 왼쪽(줄을 넘길 수 있음), 주요 행동은 카드 오른쪽 끝에 고정.
  ///   예전에는 버튼이 왼쪽부터 나열돼 확정이 묶음의 마지막 항목처럼 보였다.
  Widget _actionRow(BuildContext context,
      {List<Widget> secondary = const [], List<Widget> primary = const []}) {
    // [DU517] 이전에는 Row[Expanded(보조) · 주요] 라서 주요 버튼이 넓으면(320×640 · 2.0 의 '계약서 작성') 보조 칸이 한 글자 폭으로
    //   눌려 '확정취소'가 '확/정/취/소'로 세로로 쪼개졌다(DU515 r3 B-MULTI). 두 묶음이 한 줄에 다 들어가면 이전과 같은 자리
    //   (보조 왼쪽 · 주요 오른쪽 끝 · 세로 가운데)이고, 안 들어가면 묶음째 아래 줄로 내린다(오른쪽 맞춤). 글자 크기 · 배율 · 말줄임은 건드리지 않는다.
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

  Widget _actionButton(
    BuildContext context, {
    required String label,
    required _ActionRole role,
    required VoidCallback onTap,
  }) {
    final (Color bg, Color border, Color fg) = switch (role) {
      _ActionRole.primary => (AppColors.brand, AppColors.brand, Colors.white),
      // [UI-SCREEN-CONSISTENCY.1 · 2차] 반복 명단에서 세 상자가 모두 시선을 끌었다 — 보조·위험은 테두리 없이 글자로만.
      _ActionRole.secondary =>
        (Colors.transparent, Colors.transparent, AppColors.textSecondary),
      _ActionRole.destructive =>
        (Colors.transparent, Colors.transparent, AppColors.errorDark),
      _ActionRole.urgent =>
        (AppColors.warningDark, AppColors.warningDark, Colors.white),
    };
    return InkWell(
      onTap: _isProcessing ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      // alignment·minHeight 를 주면 Wrap 안에서 가로 전체로 늘어나 버튼이 세로로 쌓인다(UI-1 실측) —
      //   높이는 상하 여백으로만 맞춘다.
      // [DU1 후속38 B2-L] 실측(B2-L-M, 392·1.0): 주 행동 '확정' 높이 37px — 공통 기준 터치 48 미만.
      //   위 주석의 부작용(minHeight·alignment → Wrap 안 가로 팽창) 없이 **주·긴급 행동만** 상하 여백으로 맞춘다.
      //   [후속39 §2] 기준 주 버튼 높이 52(터치 48 은 최소) — 글자 21 + 15.5×2 = 52. 글자 배율이 크면 글자 높이만큼 함께 커진다.
      //   보조·위험(글자 행동)은 그대로 둔다 — 반복 명단의 무게를 늘리지 않는다.
      // [DU1 구현75 F75-1] 보조·위험(글자 행동) 실제 터치가 46.4×37 이었다(거절, 감사75) — 공통 최소 48×48 미만.
      //   모양(테두리 없는 글자)·배치(왼쪽)·무게는 그대로 두고 **보이지 않는 여백만** 넓힌다: 상하 14(글자 약 21 + 28 ≈ 49 —
      //   13.5 는 실측 47.99999 로 부동소수 경계에 걸렸다, r1),
      //   좌우 12(두 글자 '거절' 26.4 + 24 = 50.4). minWidth/alignment 는 Wrap 가로 팽창을 일으켜 쓰지 않는다(위 주석).
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: role == _ActionRole.primary || role == _ActionRole.urgent
                ? 16
                : 12,
            vertical: role == _ActionRole.primary || role == _ActionRole.urgent ? 15.5 : 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Text(
          label,
          style: ResponsiveHelper.smallStyle(context, color: fg)
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ── Badges ─────────────────────────────────────────────────────────────────

  Widget _weeklyCountBadge(BuildContext context, String uid) {
    final count = _weeklyWorkCountMap[uid] ?? 0;
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 10), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text('주$count회',
              style: ResponsiveHelper.tinyStyle(context, color: color)
                  .copyWith(fontWeight: FontWeight.w600)),
        ],
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
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: ResponsiveHelper.iconSize(context, 10),
              color: AppColors.error),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text('최근 90일 노쇼 $count회',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.error)
                  .copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _contractBadge(BuildContext context, ApplicationModel app,
      {bool isPending = false}) {
    final appId = app.id;
    // [REISSUE-RECOVERY] 조회하지 못한 건은 **모른다고 말한다.**
    //   `계약서 작성 필요`로 적으면 있는 계약을 또 만들러 가고, 아무 말도
    //   안 하면 계약이 다 된 줄 안다. 둘 다 거짓이다.
    if (_contractStatusMap.isUnresolved(appId)) {
      if (isPending) return const SizedBox.shrink();
      return _iconChip(context,
          icon: Icons.help_outline,
          label: '계약 상태 확인 불가',
          color: AppColors.grey600);
    }
    final status = _contractStatusMap.statuses[appId];
    if (status == null || status.isEmpty) {
      if (isPending) return const SizedBox.shrink();
      // [DIALOG-VISUAL-CLOSE] 배지는 버튼과 같은 판정(_needsContractIssue)으로 말한다.
      //   계약서가 없다는 사실만 보고 `작성 필요`를 붙이면, 노쇼·결근 근무일이나
      //   좌석 반납처럼 버튼이 없는 행에 할 수 없는 일을 권한다(Pixel 5 10-23 관찰).
      final missing = _missingContractChip(app);
      return _iconChip(context,
          icon: missing.icon, label: missing.label, color: missing.color);
    }
    switch (status) {
      case 'pending_worker':
        return _iconChip(context,
            icon: Icons.draw_outlined,
            label: '서명대기',
            color: AppColors.warningDark);
      case 'pending_employer':
        return _chip(context,
            label: '관리자서명',
            color: AppColors.warningDark,
            bgColor: AppColors.warningDark.withValues(alpha: 0.1));
      // [R7-P1-6 §14] 끝난 것은 참고 정보 — gray. green은 `확정`에 쓴다.
      case 'completed':
        return _chip(context,
            label: '계약완료',
            color: AppColors.grey600,
            bgColor: AppColors.grey100);
      case 'voided':
        return _chip(context,
            label: '무효',
            color: AppColors.error,
            bgColor: AppColors.errorBg);
      default:
        return _chip(context,
            label: '계약중',
            color: AppColors.grey600,
            bgColor: AppColors.grey600.withValues(alpha: 0.1));
    }
  }

  // 아이콘 + 텍스트 조합 칩 — 액션이 필요한 계약 상태(미작성·서명대기)에 사용
  Widget _iconChip(BuildContext context,
      {required IconData icon, required String label, required Color color}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      // [R7-P1-2 DEVICE.1H.1] 글자가 커지면 `계약서 작성 필요` 가 Wrap 의 남은
      //   폭을 넘어 칩 안에서 잘렸다. 값을 줄이지 않고 **두 줄로 흐르게** 한다.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              label,
              style: ResponsiveHelper.tinyStyle(context, color: color)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }


  Widget _chip(BuildContext context,
      {required String label,
      required Color color,
      required Color bgColor}) {
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
      child: Text(label,
          style: ResponsiveHelper.tinyStyle(context, color: color)
              .copyWith(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildGroupStats(BuildContext context, _GroupData g) {
    // [GAP-DAD-STAFFING-RELEASED-01 FIX] staffingReleased 좌석 반납 앱 제외 — NO_SHOW 반납 후 FULL 오판정 방지
    final confirmed = g.seatedConfirmed;
    final pending = g.pendingApps.length;
    final required = g.requiredCount;
    final isFull = required > 0 && confirmed >= required;
    final statusColor = isFull ? AppColors.successDark : AppColors.infoDark;

    // [R7-P1-2 DEVICE.1H.1] 고정 Row 라 글자가 커지면 머리줄이 넘쳤다.
    //   아이콘과 그 숫자는 한 덩어리로 붙여 두고, **덩어리끼리** 줄을 넘긴다.
    //   수치를 지우거나 합치지 않는다 — 지원과 초대는 다른 사실이다.
    return Wrap(
      spacing: ResponsiveHelper.spacing(context, 6),
      runSpacing: ResponsiveHelper.spacing(context, 2),
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _statGroup(
          context,
          icon: isFull ? Icons.check_circle : Icons.people_outline,
          iconSize: 14,
          label: required > 0 ? '$confirmed/$required명' : '$confirmed명',
          color: statusColor,
        ),
        // [SYSTEM-INTEGRATION-R2.2] 지원 대기와 초대 중을 합치지 않는다.
        //   하나로 합치면 몇이 내가 보낸 초대이고 몇이 들어온 지원인지 모른다.
        if (pending > 0)
          _statGroup(context,
              icon: Icons.schedule,
              label: '지원 $pending',
              // [UI-SCREEN-CONSISTENCY.1] 지원 수는 사실 — 정원(확정/필요)만 강조한다.
              color: AppColors.textSecondary),
        // [SYSTEM-INTEGRATION-R2.2.1] 지금 수락될 수 있는 초대만 센다.
        if (g.activeInvites.isNotEmpty)
          _statGroup(context,
              icon: Icons.send_outlined,
              label: '초대 ${g.activeInvites.length}',
              color: AppColors.infoDark),
        // [R2.2.1 CORRECTION] capacity 를 모르는 초대는 숫자 대신 물음표로 둔다.
        if (g.unknownInvites.isNotEmpty)
          _statGroup(context,
              icon: Icons.help_outline,
              label: '초대 ?',
              color: AppColors.grey500),
      ],
    );
  }

  /// 아이콘과 그 수치는 떨어지면 뜻을 잃는다 — 한 덩어리로 유지한다.
  Widget _statGroup(BuildContext context,
      {required IconData icon,
      required String label,
      required Color color,
      double iconSize = 12}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon,
            size: ResponsiveHelper.iconSize(context, iconSize), color: color),
        SizedBox(width: ResponsiveHelper.spacing(context, 2)),
        // 한 덩어리가 남은 폭보다 넓어지는 마지막 한 픽셀까지 접히게 둔다.
        Flexible(
          child: Text(
            label,
            style: ResponsiveHelper.smallStyle(context, color: color)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  /// [R2.2.1 CORRECTION] 인력 현황을 읽지 못했을 때 충원 CTA 자리에 서는 안내.
  ///
  ///   CTA가 사라진 이유가 `부족 0`이 아니라 `읽지 못함`임을 말한다.
  /// [R7-P1-PRODUCT] 장기 부족의 충원 경로 안내.
  ///
  /// 이 화면에서 장기 초대를 보낼 수 없는 것은 권한이나 상태 때문이 아니라
  /// **아직 그 경로가 없기 때문**이다. 이유를 말하지 않고 버튼만 없으면
  /// 관리자는 부족을 보고 들어와 아무것도 하지 못한 채 되돌아간다.
  Widget _buildLongTermInviteHint(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
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
          const Icon(Icons.info_outline, size: 16, color: AppColors.grey600),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '장기 공고 충원은 공고 목록의 ⋮ 메뉴에서 보낼 수 있어요.',
              style:
                  ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityUnknownNotice(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
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
            // [DU523] 320×640 · 2.0 에서 '확인/하지'처럼 낱말 안에서 끊겼다(DU519 합성 B-UNK) — 줄바꿈은 공백 · 개행에서만.
            //   읽는 이름 · 글 원문(toPlainText)은 그대로다(span 의 semanticsLabel · DU519 와 같은 방식).
            child: Text.rich(
              TextSpan(
                text: TextLayout.keepWords(
                    '인력 현황을 확인하지 못해 충원이 필요한지 알 수 없어요.\n새로고침 후 다시 확인해 주세요.'),
                semanticsLabel:
                    '인력 현황을 확인하지 못해 충원이 필요한지 알 수 없어요.\n새로고침 후 다시 확인해 주세요.',
              ),
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
          ),
        ],
      ),
    );
  }

  // ── [SYSTEM-INTEGRATION-R2.2] 초대 현황 ────────────────────────────────────

  /// 초대의 현재 의미 — canonical status + 기존 signal에서 읽는다.
  /// 새 enum을 만들지 않는다.
  ///
  /// [R2.2.1] INVITED는 capacity를 함께 봐야 의미가 정해진다. 자리가 찼는데도
  /// `초대 중`이라고 하면 관리자는 오지 않을 응답을 기다린다 — 근로자 화면은
  /// 이미 `모집이 완료된 초대예요`라고 말하고 서버도 수락을 거부하는 상태다.
  (String, Color) _inviteStateLabel(
    ApplicationModel app, {
    InviteCapacityState capacity = InviteCapacityState.unknown,
  }) =>
      // [E2-INVITED-SEAT] 업무별 창과 같은 문구를 쓰도록 공용 함수로 옮겼다.
      inviteStateLabelOf(app, capacity: capacity);

  Widget _buildInviteSection(BuildContext context, _GroupData g) {
    // 조회 실패를 '초대 중 0명'으로 바꾸지 않는다 (ERROR != ZERO).
    if (_dayInvitations == null) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 6),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 14, color: AppColors.errorDark),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            // [DU518] 글이 칸보다 길면(320×640 · 2.0) 오른쪽으로 117px 넘쳤다(DU515 r3 B-UNK) — 남은 폭 안에서 아래 줄로 넘긴다.
            //   한 줄에 들어가는 폭에서는 자리 그대로다. 글 · 색 · 크기는 그대로.
            Expanded(
              // [DU519] 아래 줄로 넘길 때 '확인하/지'처럼 낱말 안에서 끊겼다(DU518 B-UNK) — 줄바꿈은 공백에서만.
              //   읽는 이름 · 글 원문(toPlainText)은 그대로 '초대 현황을 확인하지 못했어요' 다(span 의 semanticsLabel).
              child: Text.rich(
                TextSpan(
                  text: TextLayout.keepWords('초대 현황을 확인하지 못했어요'),
                  semanticsLabel: '초대 현황을 확인하지 못했어요',
                ),
                style: ResponsiveHelper.smallStyle(context, color: AppColors.errorDark),
              ),
            ),
          ],
        ),
      );
    }

    // [R2.2.1] 아직 응답하지 않은 초대를 capacity로 가른다.
    //   상태(INVITED)는 그대로 두고 지금의 의미만 나눈다 — 자리가 다시 열리면
    //   같은 초대가 다시 `초대 중`으로 돌아온다.
    //   [R2.2.1 CORRECTION] capacity를 모르는 초대는 어느 쪽에도 넣지 않는다.
    //   `초대 중`에 넣으면 수락을 기다리라는 말이 되고, `모집 완료`에 넣으면
    //   끝났다는 말이 된다. 둘 다 확인한 적 없는 주장이다.
    final outstanding = g.activeInvites;
    final stale = g.staleInvites;
    final unitClosed = g.unitClosedInvites;
    final unknown = g.unknownInvites;

    // 끝난 초대는 최근 3건만 — 기록 전체를 운영 화면에 펼치지 않는다.
    //   수락도 초대의 결과다. 확정 명단에만 두면 그 확정이 초대에서 왔다는
    //   사실이 사라진다(§5 provenance).
    final closed = [...g.closedInvites, ...g.acceptedInvites]
      ..sort((a, b) => (b.invitedAt ?? b.appliedAt).compareTo(a.invitedAt ?? a.appliedAt));
    final recentClosed = closed.take(3).toList();
    if (outstanding.isEmpty && stale.isEmpty && unitClosed.isEmpty &&
        unknown.isEmpty && recentClosed.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (outstanding.isNotEmpty) ...[
          // [INVITE-CLOSURE-PROJECTION] 공개 모집이 끝나도 이미 보낸 초대는
          //   기한까지 유효하다 — 관리자가 `모집 종료`로 읽고 포기하지 않게 말한다.
          _sectionDivider(
              context,
              g.invitesOutliveIntake
                  ? '초대 중 · 공개 모집 마감 (${outstanding.length}명)'
                  : '초대 중 (${outstanding.length}명)',
              AppColors.infoDark),
          ...outstanding.map((a) => _buildInviteRow(context, a,
              capacity: InviteCapacityState.available)),
        ],
        if (stale.isNotEmpty) ...[
          _sectionDivider(
              context, '모집 완료 · 정원 마감 (${stale.length}명)', AppColors.grey500),
          ...stale.map((a) =>
              _buildInviteRow(context, a, capacity: InviteCapacityState.full)),
        ],
        if (unitClosed.isNotEmpty) ...[
          _sectionDivider(
              context, '모집 종료 (${unitClosed.length}명)', AppColors.grey500),
          ...unitClosed.map((a) =>
              _buildInviteRow(context, a, capacity: InviteCapacityState.closed)),
        ],
        if (unknown.isNotEmpty) ...[
          _sectionDivider(
              context, '상태 확인 불가 (${unknown.length}명)', AppColors.grey500),
          ...unknown.map((a) => _buildInviteRow(context, a,
              capacity: InviteCapacityState.unknown)),
        ],
        if (recentClosed.isNotEmpty) ...[
          _sectionDivider(context, '최근 초대 응답', AppColors.grey500),
          ...recentClosed.map((a) => _buildInviteRow(context, a)),
        ],
      ],
    );
  }

  Widget _buildInviteRow(
    BuildContext context,
    ApplicationModel app, {
    InviteCapacityState capacity = InviteCapacityState.unknown,
  }) {
    final (label, color) = _inviteStateLabel(app, capacity: capacity);
    final user = _userMap[app.uid];
    final name = user?.displayName ?? user?.name ?? app.applicantName ?? '근무자';
    final sentAt = app.invitedAt;
    // [INVITE-PREACCEPT] 대기 중인 초대는 눌러서 근로자 상세를 연다 —
    //   거기의 `서류 확인` 영역이 동의 여부·현재 문서 버전·검토를 서버
    //   판정대로 보여준다. 이 입구가 없어서 관리자가 초대받은 사람의
    //   서류를 확인할 방법이 없었고, 그 결과 근로자가 수락할 수 없었다.
    //   끝난 초대(거절·만료·철회)는 열지 않는다 — 검토할 지원이 아니다.
    final canOpen = app.status == AppStatus.invited && user != null;
    return InkWell(
      onTap: canOpen ? () => _showInvitedWorkerDetail(app, user) : null,
      child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 20),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (sentAt != null)
                  Text(
                    '${FormatHelper.formatDateTime(sentAt)} 발송',
                    style: ResponsiveHelper.smallStyle(
                        context, color: AppColors.grey500),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // [R7-P1-2 DEVICE.1H.1] 상태 배지가 고정 폭이라, 글자가 커지면
          //   `초대 수락 · 확정` 처럼 긴 라벨이 행 밖으로 나갔다. 이 라벨은
          //   초대가 어떻게 끝났는지를 말하는 값이라 줄이지 않는다 — 대신
          //   배지 자체가 남은 폭 안에서 두 줄로 흐르게 한다.
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: ResponsiveHelper.smallStyle(context, color: color)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (canOpen) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.grey400),
          ],
        ],
      ),
      ),
    );
  }

  /// [INVITE-PREACCEPT] 초대받은 근로자 상세 — **승인 버튼 없이** 연다.
  ///
  /// 초대는 관리자가 확정하는 것이 아니라 근로자가 수락하는 것이다. 여기서
  /// 관리자가 하는 일은 서류 확인뿐이고, 그 판정·권한·버전 검사는 상세의
  /// `서류 확인` 영역이 서버(callableGetApplicantDocumentReview 등)로 한다.
  /// 확인 결과는 초대 상태를 바꾸지 않으므로 목록 갱신은 닫힌 뒤 한 번만 한다.
  Future<void> _showInvitedWorkerDetail(ApplicationModel app, UserModel user) async {
    await WorkerDetailDialog.show(
      context: context,
      user: user,
      application: app,
      businessId: _selectedBusinessId,
      isConfirmed: false,
      showApprovalButtons: false,
    );
    if (mounted) await _load();
  }

  // ── ID Card Request ────────────────────────────────────────────────────────

  Widget _buildIdCardRequestSection(
      BuildContext context, _GroupData g, int requestableCount) {
    final isActive = _idCardSelectGroupKey == g.groupKey;
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      // [COMMON-TEXT-LAYOUT.28] 안내와 버튼이 한 줄을 나눠 '요청 가능 / 6명' 으로 갈렸다 — 좁으면 버튼을 아래로.
      child: AdaptiveActionRow(
        minRowWidth: 220,
        leading: Row(
        children: [
          // [UI-SCREEN-CONSISTENCY.1] 일괄 패널도 행 버튼과 같은 기준 — 안내는 중립, 채움은 실행 하나.
          Icon(Icons.badge,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.grey600),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              isActive
                  ? '${_selectedIdCardUserIds.length}명 선택됨'
                  // [R7-P1-4 §12] `미요청`은 none·expired·rejected 셋을 한
                  //   낱말로 덮었다. 거절당한 사람과 아직 요청하지 않은 사람이
                  //   같아 보였고, 만료된 건은 다시 요청해야 한다는 사실이
                  //   사라졌다. 이 숫자의 canonical 의미는
                  //   IdCardHelper.isRequestable — `지금 요청할 수 있는 사람`이다.
                  //   원천 상태는 건드리지 않고 집계 이름만 그 뜻에 맞춘다.
                  : TextLayout.keepWords('요청 가능 $requestableCount명'),
              semanticsLabel: isActive
                  ? '${_selectedIdCardUserIds.length}명 선택됨'
                  : '요청 가능 $requestableCount명',
              style: ResponsiveHelper.bodyStyle(context,
                  color: AppColors.textPrimary),
            ),
          ),
        ]),
        actions: [
          if (isActive && _selectedIdCardUserIds.isNotEmpty)
            InkWell(
              onTap: _batchRequestIdCard,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                decoration: BoxDecoration(
                  color: AppColors.brand,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('요청하기',
                    softWrap: false,
                    style: ResponsiveHelper.smallStyle(context,
                            color: Colors.white)
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
          InkWell(
            onTap: () {
              setState(() {
                if (isActive) {
                  _idCardSelectGroupKey = null;
                  _selectedIdCardUserIds.clear();
                } else {
                  _idCardSelectGroupKey = g.groupKey;
                  _selectAllRequestableUsers(g);
                  // 다른 모드와 상호 배제
                  _isBatchMode = false;
                  _selectedIds.clear();
                  _contractBatchGroupKey = null;
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 6),
              ),
              decoration: BoxDecoration(
                color: isActive ? AppColors.grey100 : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isActive ? '취소' : '신분증 요청',
                softWrap: false,
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: isActive ? AppColors.grey700 : AppColors.brand,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectAllRequestableUsers(_GroupData g) {
    _selectedIdCardUserIds.clear();
    for (final app in g.confirmedApps) {
      final user = _userMap[app.uid];
      if (user == null) continue;
      if (IdCardHelper.isRequestable(_idCardStatusMap[user.uid] ?? 'none')) {
        _selectedIdCardUserIds.add(user.uid);
      }
    }
  }

  void _toggleIdCardSelection(String uid) {
    setState(() {
      if (_selectedIdCardUserIds.contains(uid)) {
        _selectedIdCardUserIds.remove(uid);
      } else {
        _selectedIdCardUserIds.add(uid);
      }
    });
  }

  Future<void> _batchRequestIdCard() async {
    if (_isProcessing) return;
    if (_selectedIdCardUserIds.isEmpty) return;
    final currentUser = context.read<UserProvider>().currentUser;
    if (currentUser == null) {
      ToastHelper.showError('로그인이 필요합니다');
      return;
    }
    final bizId = _selectedBusinessId ?? '';
    if (bizId.isEmpty || widget.businesses.isEmpty) {
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
      return;
    }
    // [특이사항] orElse 폴백 제거 — bizId가 widget.businesses에 없으면 중단.
    // 폴백으로 첫 번째 사업장을 사용하면 잘못된 사업장 명의로 신분증 요청이 생성된다.
    final bizIdx = widget.businesses.indexWhere((b) => b.id == bizId);
    if (bizIdx < 0) return;
    final business = widget.businesses[bizIdx];

    // 선택된 사용자 정보 수집 — 확정 앱 우선, uid 중복 스킵
    final targets = <Map<String, String>>[];
    final seenUids = <String>{};
    for (final app in [..._confirmedApps, ..._pendingApps]) {
      final user = _userMap[app.uid];
      if (user == null || !_selectedIdCardUserIds.contains(user.uid)) continue;
      if (!seenUids.add(user.uid)) continue;
      targets.add({
        'uid': user.uid,
        'name': user.name,
        'applicationId': app.id,
      });
    }

    if (targets.isEmpty) {
      ToastHelper.showWarning('요청 가능한 대상이 없습니다');
      return;
    }

    if (!mounted) return;
    setState(() => _isProcessing = true);
    try {
      final successCount = await IdCardHelper.showBatchRequestDialog(
        context: context,
        firestoreService: _svc,
        requester: {'uid': currentUser.uid, 'name': currentUser.name},
        business: {'id': bizId, 'name': business.name},
        targets: targets,
      );

      if (!mounted) return;
      if (successCount > 0) {
        _hasChanges = true;
        setState(() {
          for (final uid in _selectedIdCardUserIds) {
            _idCardStatusMap[uid] = 'pending';
          }
          _idCardSelectGroupKey = null;
          _selectedIdCardUserIds.clear();
          _isProcessing = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [day_batchRequestIdCard] 신분증 요청 실패: $e');
      if (mounted) ToastHelper.showError('신분증 요청 중 오류가 발생했습니다');
    } finally {
      if (mounted && _isProcessing) setState(() => _isProcessing = false);
    }
  }

  // ── Contract Batch Section ─────────────────────────────────────────────────

  Widget _buildContractBatchSection(
      BuildContext context, _GroupData g, int noContractCount) {
    final isProcessing = _contractBatchGroupKey == g.groupKey;
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      // [COMMON-TEXT-LAYOUT.28] 버튼 이름이 '계약서 일괄작 / 성' 으로 갈렸다 — 좁으면 버튼을 아래로, 이름은 한 줄.
      child: AdaptiveActionRow(
        minRowWidth: 300,
        leading: Row(
        children: [
          Icon(Icons.description_outlined,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.grey600),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              TextLayout.keepWords('계약서 미작성 $noContractCount명'),
              semanticsLabel: '계약서 미작성 $noContractCount명',
              style: ResponsiveHelper.bodyStyle(context,
                  color: AppColors.textPrimary),
            ),
          ),
        ]),
        actions: [
          if (isProcessing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            // [R7-P4.4E.6B] 안내문과 이 CTA 가 둘 다 고정 폭이라 배율을 올리면 넘쳤다(실측 6.8px).
            // [COMMON-TEXT-LAYOUT.28] 줄이는 대신 좁으면 아래 줄로 — AdaptiveActionRow.
            InkWell(
                onTap: () => _batchCreateContracts(g),
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
                    softWrap: false,
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.brand)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _batchCreateContracts(_GroupData g) async {
    // BATCH-CONTRACT-01: 계약서 일괄작성 권한 확인
    final up = Provider.of<UserProvider>(context, listen: false);
    if (!_canForSelectedBiz((p) => p.canManageContract)) {
      ToastHelper.showWarning('계약서 관리 권한이 없습니다.');
      return;
    }
    if (_contractBatchGroupKey != null) return;
    final bizId = _selectedBusinessId ?? '';
    if (bizId.isEmpty || widget.businesses.isEmpty) {
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
      return;
    }
    // [특이사항] orElse 폴백 제거 — 잘못된 bizId 시 첫 번째 사업장 명의로 계약서가 생성되는 것을 방지.
    final bizIdx = widget.businesses.indexWhere((b) => b.id == bizId);
    if (bizIdx < 0) return;
    final business = widget.businesses[bizIdx];

    // 계약서 미작성 또는 무효 확정자 수집
    final toProcess = g.confirmedApps.where((app) {
    // [REISSUE-RECOVERY] 발송 대상 판정은 한 곳(_needsContractIssue)만 쓴다.
      return _needsContractIssue(app);
    }).toList();
    if (toProcess.isEmpty) return;

    setState(() => _contractBatchGroupKey = g.groupKey);
    try {
      List<ContractArticle>? articles;
      const String? sealBase64 = null;
      const String sealType = 'stamp';
      WorkDetailData? workDetail;

      // 1. 템플릿 선택
      articles =
          await ContractTemplateSelectorDialog.show(context, businessId: bizId);
      if (articles == null || !mounted) return;

      // 2. 인감 확인 — SubAdmin은 사업주(ownerId) 문서에서 날인 조회
      // [P4.4C-SIGNER-01] 계약의 날인은 **이 사업장의 사업주(owner)** 것이다.
      //   누가 버튼을 눌렀는지가 아니라 근로계약의 사용자(고용주) identity 가
      //   정한다. 예전에는 SubAdmin 일 때만 owner 를 썼고, 그 밖에는 호출자의
      //   날인을 썼다 — owner 가 아닌 co-admin 이 발송하면 그 사람 개인 날인이
      //   고용주 날인 자리에 찍힌다.
      // [CONTRACT-DISPATCH-B1] 앱은 owner 문서를 읽을 수 없다(목록에 ownerId 없음·users 는 본인만).
      //   서버에 있는지만 묻고, 날인은 서명 writer 가 서버에서 찍는다. 모름은 미등록이 아니다.
      final sealReady = await BusinessPostingReadiness.employerSealReady(business.id);
      if (!mounted) return;
      if (sealReady == null) {
        ToastHelper.showError('사업주 날인 상태를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
        return;
      }
      if (!sealReady) {
        if (!mounted) return;
        final goSettings = await DialogHelper.showConfirm(
          context,
          title: '사업주 날인 미등록',
          message: up.isSubAdmin
              ? '일괄 계약 발송에는 사업주 날인이 필요합니다.\n사업주에게 날인 등록을 요청해주세요.'
              : '일괄 계약 발송에는 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.',
          confirmText: up.isSubAdmin ? '확인' : '설정으로 이동',
          cancelText: '취소',
        );
        if (!mounted) return;
        if (goSettings && !up.isSubAdmin) {
          Navigator.of(context, rootNavigator: true)
              .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        }
        return;
      }

      // 3. TO에서 WorkDetailData 조회
      if (g.toId != null) {
        final to = await _reads.to(g.toId!);
        if (to != null && to.workDetails.isNotEmpty) {
          workDetail = to.workDetails
              .where((w) =>
                  w.workType == g.workType &&
                  w.startTime == g.startTime &&
                  w.endTime == g.endTime)
              .firstOrNull;
        }
      }
      if (!mounted) return;

      if (workDetail == null) {
        ToastHelper.showError('근무 정보를 찾을 수 없습니다. 공고를 확인해 주세요.');
        return;
      }

      // 4. 첫 번째 대상으로 미리보기 생성
      final firstApp = toProcess.first;
      final firstUser = _userMap[firstApp.uid];
      if (firstUser == null) {
        ToastHelper.showError('지원자 정보를 불러올 수 없습니다');
        return;
      }

      late EmploymentContractModel previewContract;
      try {
        previewContract = await ContractService().buildPreviewContract(
          application: firstApp,
          business: business,
          worker: firstUser,
          workDetail: workDetail,
          articles: articles,
        );
      } catch (e) {
        if (mounted) ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
        return;
      }
      if (!mounted) return;

      // 5. 미리보기 다이얼로그
      final confirmed = await _showBatchContractPreview(
        contract: previewContract,
        sealBase64: sealBase64,
        sealType: sealType,
        count: toProcess.length,
      );
      if (confirmed != true || !mounted) return;

      // 6. 일괄 계약서 생성 + 날인(서버가 owner 날인을 찍는다)
      final finalWorkDetail = workDetail;

      // 'sent'  = 이번에 발송됨
      // 'already' = 서버가 이미 발송된 근무라고 답함 — 다시 시도할 일이 아니다
      // 'failed'  = 실제 실패
      Future<String> processOne(ApplicationModel app) async {
        final user = _userMap[app.uid];
        if (user == null) return 'failed';
        try {
          final contract = await ContractService().findOrCreateContract(
            application: app,
            business: business,
            worker: user,
            workDetail: finalWorkDetail,
            articles: articles!,
          );
          await ContractService().saveEmployerSignature(contract: contract);
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
      final List<ApplicationModel> successApps = [];
      for (var i = 0; i < toProcess.length; i += batchSize) {
        final batch =
            toProcess.sublist(i, min(i + batchSize, toProcess.length));
        final results = await Future.wait(batch.map(processOne));
        if (!mounted) return;
        for (var j = 0; j < batch.length; j++) {
          if (results[j] == 'sent') {
            successCount++;
            successApps.add(batch[j]);
          } else if (results[j] == 'already') {
            alreadyCount++;
            // [BULK-DISPATCH] 목록이 낡아 다시 누른 경우다. 다만 그 계약이
            //   지금 **어느 상태인지는 모른다** — 근로자가 이미 서명했을 수도
            //   있다. `pending_worker` 로 적으면 완료된 계약을 서명대기로
            //   보여 준다. 추측하지 않고 아래에서 서버를 다시 읽는다.
          }
        }
      }

      if (!mounted) return;
      final failedCount = toProcess.length - successCount - alreadyCount;
      if (failedCount > 0) {
        ToastHelper.showWarning(
            '$successCount/${toProcess.length}명 계약서 발송 완료. 실패한 $failedCount건은 다시 시도해주세요.');
      } else if (alreadyCount > 0) {
        ToastHelper.showSuccess(successCount > 0
            ? '$successCount명에게 계약서가 발송되었습니다 ($alreadyCount건은 이미 발송된 근무)'
            : '$alreadyCount건은 이미 계약서가 발송된 근무예요');
      } else {
        ToastHelper.showSuccess('${toProcess.length}명에게 계약서가 발송되었습니다');
      }
      if (successCount > 0) {
        _hasChanges = true;
        setState(() {
          for (final app in successApps) {
            _contractStatusMap = _contractStatusMap.withStatus(app.id, 'pending_worker');
          }
        });
      }
      if (alreadyCount > 0) {
        _hasChanges = true;
        await _load();
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했습니다');
      debugPrint('❌ 계약서 일괄 발송 실패: $e');
    } finally {
      if (mounted) setState(() => _contractBatchGroupKey = null);
    }
  }

  Future<bool?> _showBatchContractPreview({
    required EmploymentContractModel contract,
    required String? sealBase64,
    String sealType = 'stamp',
    required int count,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false, // CSN-06: 미리보기 중 실수 닫힘 방지 (취소 버튼으로만 닫기)
      builder: (ctx) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 32),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                color: Theme.of(ctx).primaryColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '근로계약서 미리보기',
                      style: ResponsiveHelper.subtitleStyle(ctx).copyWith(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    icon: const Icon(Icons.close,
                        color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.grey100,
              child: Text(
                '아래 조건으로 선택된 $count명에게 계약서가 발송됩니다.\n이름·생년월일 등 개인정보는 각 근무자별로 적용됩니다.',
                style: ResponsiveHelper.smallStyle(ctx, color: AppColors.textPrimary),
                textAlign: TextAlign.center,
              ),
            ),
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
                      child: Text('$count명에게 발송'),
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

  // ── 확정 취소 ──────────────────────────────────────────────────────────────

  /// [BUG-CANCEL-01] 확정취소 가능 여부 판단
  ///
  /// 단기 근무: 당일 checkIn 기록이 있으면 이미 근무한 것 → 취소 불가
  /// 장기 근무: 계약 시작일(workDate)이 widget.date 이전이면 이미 근무 시작 → 취소 불가
  ///            (workDate == widget.date는 첫 근무일 당일 — 아직 출근 전이면 취소 허용)
  /// 이 화면의 날짜에 대체 인력 충원이 의미 있는가 — 당일만.
  ///
  /// [PREDEVICE-PAST-REPLACEMENT] 자동 노쇼는 06:00에 "어제" 근무를 NO_SHOW로
  /// 기록한다. 그 기록은 좌석을 반납하지 않으므로 다른 조건(NO_SHOW · 단기 ·
  /// 미반납 · 권한)이 모두 맞고, 근무 탭은 과거 날짜로 이 화면을 연다.
  /// 끝난 근무에 대체충원 버튼이 뜨면 이미 지나간 날짜에 다시 사람을 구하는
  /// 상태가 만들어진다(totalConfirmed 감소, FULL→ACTIVE).
  ///
  /// 근태 화면(AttendanceStatusDialog)이 이미 쓰는 것과 같은 당일 게이트다.
  /// 과거 NO_SHOW 기록과 '대체 충원 진행 중' 배지는 그대로 보인다 —
  /// 막는 것은 action뿐이다.
  bool get _isReplacementActionable {
    final todayKst = FormatHelper.toKstDate(DateTime.now());
    final dateKst = FormatHelper.toKstDate(widget.date);
    return dateKst.isAtSameMomentAs(todayKst);
  }

  bool _canCancelConfirmation(ApplicationModel app) {
    // 당일 출근 기록 체크 (단기·장기 공통)
    if (_hasWorkedMap[app.uid] == true) return false;
    // 장기 근무자: 계약 시작일 이후 날짜를 보고 있는 경우 취소 불가
    // [특이사항] workEndDate == null 인 무기한 계약도 동일하게 처리됨
    if (app.isLongTermApplication) {
      // [BUG-FIX] workDate 직접 사용 → desiredStartDate ?? workDate
      // desiredStartDate는 희망 시작일(슬롯 날짜), workDate는 계약 기본 날짜
      // 장기 근무자가 특정 슬롯 날짜부터 시작하는 경우 desiredStartDate가 실제 시작일
      final effectiveStart = app.desiredStartDate ?? app.workDate;
      final contractStart = DateTime(
          effectiveStart.year, effectiveStart.month, effectiveStart.day);
      final viewDate = DateTime(
          widget.date.year, widget.date.month, widget.date.day);
      if (contractStart.isBefore(viewDate)) return false;
    }
    return true;
  }


  Future<void> _cancelConfirmation(ApplicationModel app) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final user = _userMap[app.uid];
      // [BUG-FIX-2] 확정 취소 사유 수집 + cancelConfirmedApplication으로 교체
      //   work_applicants_dialog과 동일 패턴 적용 (cancelReason 감사 이력 기록)
      // [CONFIRM-CANCEL-COPY] 지원 거절 창이 아니라 확정 취소 전용 창(사유·버튼·기본 문구).
      final reason = await DialogHelper.showConfirmCancelReasonPicker(
        context,
        message: user?.name != null
            ? '${user!.name}님의 확정된 근무를 취소합니다.\n취소 사유를 선택해 주세요.'
            : null,
      );
      if (reason == null || !mounted) return;
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      await _svc.cancelConfirmedApplication(
        app.id,
        canceledBy: adminUID,
        cancelReason: reason,
      );
      _hasChanges = true;
      if (!mounted) return;
      ToastHelper.showSuccess('확정이 취소되었습니다');
      await _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── [R5.1] 대체 인력 충원 ──────────────────────────────────────────────────

  /// [R7-P1-CORR] 좌석 반납은 정원 카운터를 움직인다 — 두 번 실행되면 정원이
  ///   두 번 복구된다. `_isProcessing` 체크와 설정 사이에 확인 다이얼로그
  ///   await가 있어 그 구간에 들어온 두 번째 탭이 통과할 수 있었다.
  Future<void> _releaseNoshowSeat(ApplicationModel app) =>
      ActionGuard.runVoid(
        ActionGuard.keyOf('releaseNoshowSeat', [app.id]),
        () => _releaseNoshowSeatInner(app),
      );

  Future<void> _releaseNoshowSeatInner(ApplicationModel app) async {
    if (_isProcessing) return;
    final user = _userMap[app.uid];
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '대체 인력 충원',
      message:
          '${user?.name ?? '해당 근무자'}의 NO_SHOW 자리를 반납하여 대체 인력 모집을 시작합니다.\n'
          '기존 확정 이력은 유지되며, 모집 정원이 복구됩니다.',
      confirmText: '충원 시작',
      cancelText: '취소',
      confirmColor: AppColors.warning,
    );
    if (!confirmed || !mounted) return;
    // [R7-P1-CORR] await 뒤 재확인. ActionGuard가 이미 막지만, 이 가드는
    //   같은 화면의 **다른** 처리(일괄 확정 등)와도 겹치면 안 된다.
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final success = await _svc.releaseNoshowSeat(applicationId: app.id);
      if (!mounted) return;
      if (success) {
        _hasChanges = true;
        ToastHelper.showSuccess('대체 인력 모집이 시작되었습니다');
        await _load();
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── 개별 계약서 작성 ────────────────────────────────────────────────────────

  /// [CONFIRM-TO-CONTRACT.21] 확정 직후 이 한 명에게 계약서를 이어 쓸 것인가 — 명단 재조회를
  ///   기다리지 않고 같은 세 사실(확정 지원서·계약 없음 확인·근태 가드)만 한 라운드로 읽는다.
  ///   판정 규칙은 [_needsContractIssue] 와 같다. 확정 명단·계약 상태 읽기가 실패하면 던진다
  ///   (호출부가 재조회 경로로 돌아간다). 근태 실패는 `모름` 으로 두어 단기는 잇지 않는다.
  Future<ApplicationModel?> _contractEntryFor(String appId) async {
    final bizId = _selectedBusinessId;
    if (bizId == null) throw StateError('사업장 없음');
    final attFuture = _reads.contractAttendances
        ?.call(businessId: bizId, date: widget.date)
        .then<List<AttendanceModel>?>((v) => v, onError: (Object e) {
      debugPrint('⚠️ [NOSHOW-CONTRACT-GUARD] 근태 조회 실패 — 계약 발행 판정 보류: $e');
      return null;
    });
    final r = await Future.wait<Object?>([
      _reads.confirmedWorkers(date: widget.date, businessId: bizId),
      _reads.contractStatusBatch([appId], businessId: bizId),
      attFuture ?? Future<List<AttendanceModel>?>.value(null),
    ]);
    final fresh = (r[0] as List<ApplicationModel>)
        .where((a) => a.id == appId)
        .firstOrNull;
    if (fresh == null) return null;
    final status = r[1] as ContractStatusBatch;
    final blocked = ContractAttendanceGate.blockedIds(
        [fresh], r[2] as List<AttendanceModel>?);
    final issue = status.isMissingContract(fresh.id) &&
        fresh.isContractIssuable &&
        ContractAttendanceGate.clearForIssue(fresh, blocked);
    return issue ? fresh : null;
  }

  /// [listRefresh] — 확정 직후 진입에서 아직 끝나지 않은 명단 재조회. 템플릿을 고른 뒤
  ///   근무 그룹을 찾기 전에 기다린다(사람이 고르는 동안 끝난다).
  Future<void> _createContractForOne(ApplicationModel app,
      {Future<void>? listRefresh}) async {
    if (_isProcessing) return;
    final bizId = _selectedBusinessId ?? '';
    if (bizId.isEmpty || widget.businesses.isEmpty) return;
    // [특이사항] orElse 폴백 제거 — 잘못된 bizId 시 첫 번째 사업장 명의로 계약서가 생성되는 것을 방지.
    final bizIdx = widget.businesses.indexWhere((b) => b.id == bizId);
    if (bizIdx < 0) return;
    final business = widget.businesses[bizIdx];
    var user = _userMap[app.uid];
    if (user == null && listRefresh != null) {
      setState(() => _isProcessing = true);
      await listRefresh;
      if (!mounted) return;
      setState(() => _isProcessing = false);
      user = _userMap[app.uid];
    }
    if (user == null) {
      ToastHelper.showError('지원자 정보를 불러올 수 없습니다');
      return;
    }
    setState(() => _isProcessing = true);

    // 1. 템플릿 선택
    final articles =
        await ContractTemplateSelectorDialog.show(context, businessId: bizId);
    if (articles == null || !mounted) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }
    if (listRefresh != null) {
      await listRefresh;
      if (!mounted) return;
    }

    // 2. 인감 확인 — SubAdmin은 사업주(ownerId) 문서에서 날인 조회
    final up = context.read<UserProvider>();
    // [P4.4C-SIGNER-01] 계약 날인은 이 사업장의 사업주(owner) 것이다.
    // [CONTRACT-DISPATCH-B1] 서버에 있는지만 묻는다(위 일괄과 같은 판정). 모름은 미등록이 아니다.
    const String? sealBase64 = null;
    const String sealType = 'stamp';
    final sealReady = await BusinessPostingReadiness.employerSealReady(business.id);
    if (!mounted) return;
    if (sealReady == null) {
      ToastHelper.showError('사업주 날인 상태를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
      setState(() => _isProcessing = false);
      return;
    }
    if (!sealReady) {
      if (!mounted) {
        return;
      }
      final goSettings = await DialogHelper.showConfirm(
        context,
        title: '사업주 날인 미등록',
        message: up.isSubAdmin
            ? '계약 발송에는 사업주 날인이 필요합니다.\n사업주에게 날인 등록을 요청해주세요.'
            : '계약 발송에는 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.',
        confirmText: up.isSubAdmin ? '확인' : '설정으로 이동',
        cancelText: '취소',
      );
      if (!mounted) {
        return;
      }
      if (goSettings && !up.isSubAdmin) {
        Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      }
      setState(() => _isProcessing = false);
      return;
    }

    // 3. TO에서 WorkDetailData 조회 — 해당 앱이 속한 그룹 탐색
    _GroupData? group;
    for (final g in _buildGroups()) {
      if (g.confirmedApps.any((a) => a.id == app.id)) {
        group = g;
        break;
      }
    }
    WorkDetailData? workDetail;
    // [CONFIRM-TO-CONTRACT.21] 확정 직후 진입에서 명단 재조회가 실패했으면 그룹이 없다 —
    //   그룹 값은 원래 지원서 필드에서 온다(_buildGroups). 재조회 실패가 판정된 진입을 막지 않게
    //   그 지원서 자신의 값을 쓴다. 근무 정보 대조는 아래 TO 조회 그대로다.
    final fromApp = group == null && listRefresh != null;
    final toId = fromApp ? app.toId : group?.toId;
    final groupWorkType = fromApp ? app.selectedWorkType : group?.workType;
    final groupStartTime = fromApp ? app.startTime : group?.startTime;
    final groupEndTime = fromApp ? app.endTime : group?.endTime;
    if (toId != null) {
      setState(() => _isProcessing = true);
      try {
        final to = await _reads.to(toId);
        if (to != null && to.workDetails.isNotEmpty) {
          workDetail = to.workDetails
              .where((w) =>
                  w.workType == groupWorkType &&
                  w.startTime == groupStartTime &&
                  w.endTime == groupEndTime)
              .firstOrNull;
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
    if (!mounted) return;
    if (workDetail == null) {
      // [DART-HIGH-1-FIX] toId==null 경로에서 _isProcessing=true 상태로 return하면 버튼 영구 비활성화
      // toId!=null 경로는 finally에서 해제되지만 toId==null 경로는 해제 코드 없음
      if (mounted) setState(() => _isProcessing = false);
      ToastHelper.showError('근무 정보를 찾을 수 없습니다');
      return;
    }

    // 4. 미리보기 생성
    setState(() => _isProcessing = true);
    late EmploymentContractModel previewContract;
    try {
      previewContract = await ContractService().buildPreviewContract(
        application: app,
        business: business,
        worker: user,
        workDetail: workDetail,
        articles: articles,
      );
    } catch (e) {
      if (mounted) ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
      return;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
    if (!mounted) return;

    // 5. 미리보기 다이얼로그 (1명)
    final confirmed = await _showBatchContractPreview(
      contract: previewContract,
      sealBase64: sealBase64,
      sealType: sealType,
      count: 1,
    );
    if (confirmed != true || !mounted) return;

    // 6. 계약서 생성 + 날인
    setState(() => _isProcessing = true);
    try {
      final contract = await ContractService().findOrCreateContract(
        application: app,
        business: business,
        worker: user,
        workDetail: workDetail,
        articles: articles,
      );
      await ContractService().saveEmployerSignature(contract: contract);
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

  // ── Batch Action Bar ───────────────────────────────────────────────────────

  Widget _buildBatchActionBar(BuildContext context) {
    final brand = Theme.of(context).primaryColor;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.05),
        border: Border(top: BorderSide(color: brand.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          // [BULK-PROGRESS] 처리 중에는 선택 인원 대신 진행 상황을 말한다.
          if (_batchProgress != null) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: brand),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text('처리 중 ${_batchProgress!.done}/${_batchProgress!.total}',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                    fontWeight: FontWeight.bold, color: brand)),
          ] else ...[
            Icon(Icons.check_circle_rounded, size: 14, color: brand),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text('${_selectedIds.length}명 선택',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                    fontWeight: FontWeight.bold, color: brand)),
          ],
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => _selectedIds.clear()),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.grey500,
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8), vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('해제', style: TextStyle(fontSize: 12)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _batchApprove,
            icon: Icon(Icons.check_circle_outline,
                size: ResponsiveHelper.iconSize(context, 14)),
            label: const Text('일괄 확정',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: brand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 10),
                vertical: 6,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Bar ─────────────────────────────────────────────────────────────

  Widget _buildBottomBar(BuildContext context) {
    // top-right X 버튼이 기본 닫기 역할 — footer는 접근성 보조용 slim 버튼만 유지
    return AppModalFooter(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context, _hasChanges),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              // [DU526] 기본 글자 크기(390×844)에서 받는 자리가 64×40 이었다(DU524 관측 foot48=false) — 세로 최소 48.
              //   글 · 색 · 글자 크기는 그대로이고 버튼 상자만 8 커진다(큰 글자에서는 이미 49 라 변화 없음). 공용 AppModalFooter 는 그대로.
              minimumSize: const Size(64, 48),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('닫기',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _approveApp(ApplicationModel app) async {
    if (_isProcessing) return;
    // [DART-HIGH-2-FIX] 개별 확정 시 정원 초과 체크 — _batchApprove에는 있으나 단일 확정에 누락
    final groups = _buildGroups();
    for (final g in groups) {
      if (g.confirmedApps.any((a) => a.id == app.id)) continue; // 이미 confirmed면 체크 불필요
      // [8.1E.4] groupKey와 동일한 우선순위: wdId 우선, composite fallback, legacy fallback
      final wKey = app.wdId?.isNotEmpty == true
          ? app.wdId!
          : (app.workDetailId?.isNotEmpty == true
              ? app.workDetailId!
              : '${app.selectedWorkType}_${app.startTime}_${app.endTime}');
      if (g.groupKey.endsWith('_$wKey') || g.groupKey == '${app.toId ?? app.toTitle}_$wKey') {
        if (g.requiredCount > 0 && g.confirmedApps.length >= g.requiredCount) {
          ToastHelper.showWarning('정원이 초과되어 확정할 수 없습니다 (${g.toTitle} · ${g.workType})');
          return;
        }
        break;
      }
    }
    setState(() => _isProcessing = true);
    try {
      final name = _userMap[app.uid]?.name ?? '근무자';
      final ok = await DialogHelper.showConfirm(
        context,
        title: '확정',
        message:
            '$name을(를) 계약 대기 상태로 변경하시겠습니까?\n이후 계약서를 직접 작성·서명해야 합니다.\n'
            '확정하면 바로 계약서 작성으로 이어지고, 근무자가 동의해야 출근할 수 있어요.',
        confirmText: '확정',
      );
      if (!ok || !mounted) return;
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      await _svc.updateApplicationStatus(
        applicationId: app.id,
        businessId: app.businessId,
        // [P1-A-FIX] contractPending 직접 write 제거 → confirmed CF 경유 필수
        // updateApplicationStatus(confirmed) → _confirmWithConflictCheck() → callableConfirmApplication
        // CF가 TOCTOU 잠금·충돌감지·계약서 생성 후 CONTRACT_PENDING 상태로 설정
        status: AppStatus.confirmed,
        confirmedBy: adminUID,
      );
      _hasChanges = true;
      if (!mounted) return;
      // [CONTRACT-DISPATCH-B3-HANDOFF] 계약 권한이 없으면 "작성하라"고 하지 않는다 — 발송 대기와 인계처를 말한다.
      if (_canForSelectedBiz((p) => p.canManageContract)) {
        ToastHelper.showSuccess('확정되었습니다. 계약서를 작성해 주세요.');  // [4J.0C] CONTRACT_PENDING 결과 — WorkApplicants parity
      } else {
        ToastHelper.showInfo("확정되었습니다. 계약서 발송 대기예요 — 계약 권한이 있는 관리자가 홈 '계약 미발송'에서 보낼 수 있어요.");
      }
      // [CONTRACT-BEFORE-CHECKIN] 확정 → 바로 계약서 발송(2026-10-25 사용자 지시).
      //   새 발송 경로를 만들지 않고 기존 '계약서 작성' 흐름(템플릿 → 사업주 날인 → 미리보기 → 서명)을
      //   그대로 잇는다. 근무자는 그 계약에 동의해야 출근할 수 있다(서버 callableCheckIn 판정).
      //   관리자가 중간에 닫으면 발송되지 않은 채로 남고, 행의 '계약서 작성' 버튼이 그대로 다음 일이다.
      // [CONFIRM-TO-CONTRACT.21] 명단 전체 재조회(2라운드 ~10건)를 다 기다린 뒤에야 템플릿을 열었다.
      //   판정에 필요한 것은 이 한 명의 확정 지원서·계약 상태·근무일 근태뿐이다 — 재조회를 출발시켜
      //   두고 그 셋을 한 라운드로 읽어 같은 판정(_needsContractIssue 와 같은 세 사실)을 먼저 낸다.
      //   판정 읽기가 실패하면 예전 경로(재조회 결과로 판정)로 돌아간다. 확정은 다시 요청하지 않는다.
      final reload = _load();
      final canContract = _canForSelectedBiz((p) => p.canManageContract);
      ApplicationModel? fresh;
      var decided = false;
      if (canContract) {
        try {
          fresh = await _contractEntryFor(app.id);
          decided = true;
        } catch (e) {
          debugPrint('⚠️ [CONFIRM-TO-CONTRACT] 계약 진입 판정 읽기 실패 — 명단 재조회로 판정: $e');
        }
      }
      if (!decided) {
        await reload;
        if (!mounted) return;
        final f = _confirmedAppById(app.id);
        if (f != null && _needsContractIssue(f)) fresh = f;
      }
      if (!mounted) return;
      // 계약 권한이 없으면 잇지 않는다(행의 작성 버튼과 같은 조건 — worker_detail_dialog 와 대칭)
      if (fresh != null && canContract) {
        setState(() => _isProcessing = false);
        await _createContractForOne(fresh, listRefresh: reload);
      }
      await reload;
    } on FirebaseFunctionsException catch (e) {
      // [P4.4C.2A] 계약 준비가 깨져 확정이 막힌 경우는 이유를 준비 단계로
      //   잇는다. 서버 메시지를 그대로 띄우면 `POSTING_NOT_READY:` 접두어가
      //   샌다. 지원은 취소되지 않았다는 사실도 같이 말한다.
      if (mounted) {
        if (PostingNotReady.parse(e) case final blocked?) {
          // [R7-PAYROLL-POLICY.4A §12] 이 이유만은 **그 지원자**에서 해결된다.
          //   사업장 설정으로 보내는 대신 지원 당시 기준을 보여 주고 확인을
          //   받는다. 확인하면 조건을 바꾸지 않고 그대로 확정한다.
          if (blocked.reason ==
              PostingNotReadyReason.applicationPolicyNotAcknowledged) {
            final acked = await ApplicationPolicyAcknowledgeSheet.show(
              context,
              application: app,
              workerName: _userMap[app.uid]?.name ?? '근무자',
              currentBusinessRules: widget.businesses
                  .where((b) => b.id == app.businessId)
                  .firstOrNull
                  ?.attendanceRules,
            );
            if (acked && mounted) {
              setState(() => _isProcessing = false);
              await _approveApp(app);
              return;
            }
            return;
          }
          final canSetUp = !context.read<UserProvider>().isSubAdmin;
          ToastHelper.showError(
              blocked.confirmBlockedNotice(canSetUp: canSetUp));
        } else if (_isAmbiguousConfirmError(e.code)) {
          await _reloadAfterAmbiguousConfirm();
        } else {
          ToastHelper.showError(e.message ?? '확정 처리 중 오류가 발생했습니다');
        }
      }
    } catch (e) {
      // [SIM-A] 서버 응답을 받지 못했거나 받은 뒤 클라이언트가 실패했다 —
      //   확정이 커밋됐는지 알 수 없다. 오류라고 단정하지도, 성공을 추정하지도 않는다.
      if (mounted) await _reloadAfterAmbiguousConfirm();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// [SIM-A] 서버가 거절 이유를 말한 게 아니라 **결과를 모르는** 응답인가.
  ///   커밋된 뒤 응답만 잃었을 수 있다.
  static bool _isAmbiguousConfirmError(String code) => const {
        'deadline-exceeded',
        'unavailable',
        'internal',
        'unknown',
        'cancelled',
      }.contains(code);

  /// [SIM-A] 확정 결과를 모를 때 — 성공으로 말하지 않고 서버를 다시 읽는다.
  ///
  ///   예전에는 이 경우 `확정 처리 중 오류` 를 띄우고 재조회를 건너뛰었다.
  ///   서버는 이미 확정했는데 창은 `확정` 버튼을, 카드는 `대기 1` 을 계속 보여 줬다.
  ///   다시 읽은 목록이 사실을 말한다. 상위 카드도 다시 읽도록 신호를 남긴다.
  ///   호출부의 finally 가 `_isProcessing` 을 풀기 전까지 같은 버튼은 눌리지 않는다.
  Future<void> _reloadAfterAmbiguousConfirm() async {
    ToastHelper.showWarning('확정 결과를 확인하지 못했어요. 최신 상태를 다시 불러옵니다.');
    _hasChanges = true;
    await _load();
  }

  /// [CROSS-DOMAIN-R5.3B] 다른 업무 제안.
  ///
  /// 이 화면은 하루치 여러 공고를 한 번에 보므로 슬롯의 WorkDetail 목록을
  /// 들고 있지 않다. 눌렀을 때만 그 슬롯을 읽는다 — 상시 listener나 polling을
  /// 추가하지 않는다.
  ///
  /// 읽기 실패는 "제안할 업무가 없다"가 아니다. 실패라고 말하고 아무것도
  /// 바꾸지 않는다.
  Future<void> _offerAlternativeWork(
      ApplicationModel app, UserModel? user) async {
    if (_isProcessing || !mounted) return;
    final toId = app.toId;
    final slotId = app.slotId;
    if (toId == null || slotId == null) return;
    final workerName = user?.name ?? '지원자';

    setState(() => _isProcessing = true);
    List<WorkDetailData> wds;
    try {
      wds = await _reads.slotWorkDetails(toId, slotId);
    } catch (e) {
      debugPrint('⚠️ [R5.3B] slot workDetails 조회 실패 [$toId/$slotId]: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ToastHelper.showError('업무 목록을 불러오지 못했습니다. 다시 시도해주세요.');
      }
      return;
    }
    if (!mounted) return;

    // 지금 지원한 업무 — wdId가 canonical, 없으면 후보에서 빼지 못한다.
    WorkDetailData? current;
    for (final w in wds) {
      if (w.id.isNotEmpty && w.id == app.wdId) { current = w; break; }
    }
    final candidates = AlternativeWorkOfferSheet.offerableFrom(wds, current);
    if (candidates.isEmpty) {
      setState(() => _isProcessing = false);
      ToastHelper.showWarning('제안할 수 있는 다른 업무가 없습니다.');
      return;
    }

    // 확정 인원은 이 화면에 로드된 지원서에서 센다(자연키 wdId 기준).
    int confirmedOf(WorkDetailData w) => _confirmedApps
        .where((a) => a.wdId == w.id && a.slotId == slotId)
        .length;

    setState(() => _isProcessing = false);
    // [R5.3C.1] 개별 급여 제안은 canManageWage가 따로 필요하다 — 서버도 같다.
    final picked = await AlternativeWorkOfferSheet.pickOffer(
      context,
      workerName: workerName,
      currentWork: current,
      candidates: candidates,
      confirmedCountOf: confirmedOf,
      sourceWage: app.wage,
      sourceWageType: app.wageType,
      canManageWage: _canForSelectedBiz((p) => p.canManageWage),
    );
    if (picked == null || !mounted) return;
    final target = candidates.firstWhere((w) => w.id == picked.wdId);

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
      await _load();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectApp(ApplicationModel app) async {
    if (_isProcessing || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      final userName = _userMap[app.uid]?.name ?? '지원자';
      final reason = await DialogHelper.showRejectReasonPicker(
        context,
        title: '지원 거절',
        message: '$userName님을 거절합니다.\n거절 사유를 선택해주세요.',
      );
      if (reason == null || !mounted) return;
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      await _svc.updateApplicationStatus(
        applicationId: app.id,
        status: AppStatus.rejected,
        rejectedBy: adminUID,
        message: reason.trim().isEmpty ? null : reason.trim(),
      );
      _hasChanges = true;
      if (!mounted) return;
      ToastHelper.showSuccess('거절 처리되었습니다');
      await _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('거절 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }


  Future<void> _showWorkerDetail(
    ApplicationModel app,
    UserModel? user, {
    required bool isPending,
  }) async {
    if (user == null) {
      ToastHelper.showWarning('근무자 정보를 불러올 수 없습니다');
      return;
    }
    final changed = await WorkerDetailDialog.show(
      context: context,
      user: user,
      application: app,
      businessId: _selectedBusinessId,
      isConfirmed: !isPending,
      showApprovalButtons: isPending,
      onStatusChanged: () {
        _hasChanges = true;
        _load();
      },
    );
    if (changed == true) _hasChanges = true;
  }

  Future<void> _batchApprove() async {
    // PERM-01: 실행 시점 재확인 — UI 토글이 우회되더라도 서버 전 최후 방어
    if (!_canForSelectedBiz((p) => p.canManageTo)) {
      ToastHelper.showWarning('일괄 확정 권한이 없습니다.');
      return;
    }
    if (_isProcessing || _selectedIds.isEmpty) return;

    // 정원 초과 검증 (TO별로 현재 확정 수 + 선택 수 > 정원이면 경고)
    final selectedApps = _pendingApps.where((a) => _selectedIds.contains(a.id)).toList();

    // M3: toId 없는 지원서 사전 차단
    if (selectedApps.any((a) => a.toId == null)) {
      ToastHelper.showWarning('공고 정보가 없는 지원서가 포함되어 있습니다. 개별 처리해주세요.');
      return;
    }

    // [4J.0C] TO-level canApprovePending 가드 — _toCache에 있는 TO만 검사
    // FULL/TIME_EXPIRED/POSTING_EXPIRED TO는 선제 차단 (CF도 동일 gate)
    final blockedApps = selectedApps.where((a) {
      final to = _toCache[a.toId];
      return to != null && !to.canApprovePending;
    }).toList();
    if (blockedApps.isNotEmpty) {
      ToastHelper.showWarning('현재 상태의 공고(정원 초과·만료)에서는 확정할 수 없습니다. 공고 상태를 확인해 주세요.');
      return;
    }

    // [BUG-FIX-1] workDetail(업무) 단위 정원 초과 체크
    //   이전 코드는 TO 전체 합산 정원으로 체크해 특정 업무 파트가 초과돼도 허용되는 버그 존재
    final selectedByGroupKey = <String, int>{};
    for (final app in selectedApps) {
      // [8.1E.4] groupKey와 동일한 우선순위: wdId 우선, composite fallback, legacy fallback
      final wKey = app.wdId?.isNotEmpty == true
          ? app.wdId!
          : (app.workDetailId?.isNotEmpty == true
              ? app.workDetailId!
              : '${app.selectedWorkType}_${app.startTime}_${app.endTime}');
      final key = '${app.toId ?? app.toTitle}_$wKey';
      selectedByGroupKey[key] = (selectedByGroupKey[key] ?? 0) + 1;
    }
    final groups = _buildGroups();
    final overflowLabels = <String>[];
    for (final g in groups) {
      final selectedCount = selectedByGroupKey[g.groupKey] ?? 0;
      if (selectedCount == 0) continue;
      if (g.requiredCount > 0 &&
          g.confirmedApps.length + selectedCount > g.requiredCount) {
        overflowLabels.add('${g.toTitle}(${g.workType})');
      }
    }
    if (overflowLabels.isNotEmpty) {
      final names = overflowLabels.toSet().join(', ');
      ToastHelper.showWarning('업무별 정원 초과: $names\n해당 업무의 선택 인원을 줄여주세요.');
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final count = _selectedIds.length;
      final confirmed = await DialogHelper.showConfirm(
        context,
        title: '일괄 확정',
        message:
            '선택한 $count명을 계약 대기 상태로 변경하시겠습니까?\n이후 각 지원자의 계약서를 직접 작성·서명해야 합니다.\n'
            '확정하면 바로 계약서 일괄 작성으로 이어지고, 근무자가 동의해야 출근할 수 있어요.',
        confirmText: '일괄 확정',
      );
      if (!confirmed || !mounted) return;
      final ids = _selectedIds.toList();
      final total = ids.length; // [4J.1] 부분 실패 카운트 계산용
      final confirmedIds = <String>{};
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      // [CROSS-DOMAIN-R5.1D] 서버가 지원서를 읽기 전에 인가하려면 사업장이 필요하다.
      //   선택 사업장이 비어 있을 수 있으므로 화면에 있는 지원서에서 함께 모은다.
      final bizOf = <String, String>{
        for (final g in _cachedGroups)
          for (final a in [...g.pendingApps, ...g.confirmedApps]) a.id: a.businessId,
      };
      // [P1-A-FIX] parallel Future.wait → sequential for-loop
      //   confirmed CF 경유: callableConfirmApplication은 Firestore 트랜잭션 내 충돌감지 수행.
      //   병렬 처리 시 CF 간 레이스컨디션으로 동일 슬롯 중복 확정 가능 → 순차 처리 필수.
      //   [보안] PERMISSION_DENIED 포함 실패 로그 유지 — 크로스-사업장 접근 감지용.
      int successCount = 0;
      int processed = 0;
      for (final appId in ids) {
        // [BULK-PROGRESS] 순차 처리라 인원에 비례해 걸린다 — DEV 실측 기준
        //   한 건에 약 0.26초, 60명이면 16초다. 그동안 버튼만 잠겨 있으면
        //   관리자는 멈춘 것인지 진행 중인지 알 수 없다. 몇 명째인지 말한다.
        //   (병렬로 바꾸지 않는다 — 동일 슬롯 중복 확정을 막는 순차 처리다.)
        if (mounted && total > 1) {
          setState(() => _batchProgress = (done: processed, total: total));
        }
        try {
          await _svc.updateApplicationStatus(
            applicationId: appId,
            businessId: _selectedBusinessId ?? bizOf[appId],
            // confirmed → _confirmWithConflictCheck() → CF callableConfirmApplication
            // CF가 TOCTOU 잠금·충돌감지·계약서 생성 후 CONTRACT_PENDING 설정
            status: AppStatus.confirmed,
            confirmedBy: adminUID,
          );
          successCount++;
          confirmedIds.add(appId);
        } catch (e) {
          debugPrint('❌ [_batchApprove] 확정 실패 [$appId]: $e');
        }
        processed++;
      }
      if (mounted) setState(() => _batchProgress = null);
      if (successCount > 0) _hasChanges = true;
      if (!mounted) return;
      // [4J.1] 부분 실패 피드백 — 성공/전체 카운트 표시
      // 실패 원인: network 오류 외에 TO 정원 초과(동시 확정)·Application 취소 등
      // 재시도로 해결되지 않는 케이스 포함 → "상태를 확인" 권장
      if (successCount == 0) {
        ToastHelper.showError('확정에 실패했습니다. 지원자 상태를 확인해 주세요.');
      } else if (successCount < total) {
        ToastHelper.showWarning('$successCount/$total명 확정 완료. 실패한 지원자의 상태를 확인해 주세요.');
      } else {
        ToastHelper.showSuccess('$successCount명이 확정되었습니다');
      }
      // [CONTRACT-DISPATCH-B3-HANDOFF] 일괄도 같은 사실 — 계약 권한이 없으면 발송 대기·인계처
      if (successCount > 0 && !_canForSelectedBiz((p) => p.canManageContract)) {
        ToastHelper.showInfo("계약서 발송 대기예요 — 계약 권한이 있는 관리자가 홈 '계약 미발송'에서 보낼 수 있어요.");
      }
      await _load();
      // [CONTRACT-BEFORE-CHECKIN] 일괄 확정 → 바로 기존 '계약서 일괄 작성'(모집 단위별)으로 잇는다.
      //   방금 확정된 사람이 있는 모집 단위만. 닫으면 발송되지 않은 채로 남고 단위의 일괄 작성 버튼이 다음 일이다.
      if (!mounted || confirmedIds.isEmpty || !_canForSelectedBiz((p) => p.canManageContract)) return;
      for (final g in _buildGroups()) {
        if (!mounted) return;
        if (!g.confirmedApps.any((a) => confirmedIds.contains(a.id) && _needsContractIssue(a))) continue;
        await _batchCreateContracts(g);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _genderAge(UserModel? user) {
    if (user == null) return '';
    final parts = <String>[];
    if (user.birthDate != null) {
      final now = DateTime.now();
      int age = now.year - user.birthDate!.year;
      if (now.month < user.birthDate!.month ||
          (now.month == user.birthDate!.month &&
              now.day < user.birthDate!.day)) {
        age--;
      }
      parts.add('$age세');
    }
    if (user.gender == '남성') {
      parts.add('남');
    } else if (user.gender == '여성') {
      parts.add('여');
    }
    return parts.isNotEmpty ? '(${parts.join(' ')})' : '';
  }

  /// [R7-P1-2 DEVICE.1H §4] 상대 시각에도 **무엇의** 시각인지 붙인다.
  ///
  ///   `4일 전` 만 적혀 있으면 지원인지 확정인지 계약인지 알 수 없다.
  ///   같은 값의 절대 표기는 이미 `지원 MM/DD HH:mm` 로 이름을 갖고 있다
  ///   (DEVICE.1E) — 두 표기가 같은 이름을 쓰게 맞춘다.
  ///
  ///   `appliedAt` 은 INSTANT 이므로 상대 계산은 timezone 과 무관하다.
  /// [INVITE-TIME-COPY] 초대로 들어온 사람은 **초대한 시각**을 쓴다 — 지원한 적이 없는데
  ///   `지원 N분 전` 이 붙었다(Pixel 5 10-23). 초대 시각 기록이 없으면 시간을 지어내지 않고 `초대` 만.
  String _relationTimeAgo(ApplicationModel app) {
    if (app.invitedAt != null) return _timeAgo(app.invitedAt!, label: '초대');
    if (app.invitedBy != null) return '초대';
    return _timeAgo(app.appliedAt);
  }

  String _timeAgo(DateTime dt, {String label = '지원'}) {
    final diff = DateTime.now().difference(dt);
    final String rel;
    if (diff.isNegative) {
      rel = '방금 전';
    } else if (diff.inDays >= 1) {
      rel = '${diff.inDays}일 전';
    } else if (diff.inHours >= 1) {
      rel = '${diff.inHours}시간 전';
    } else if (diff.inMinutes >= 1) {
      rel = '${diff.inMinutes}분 전';
    } else {
      rel = '방금 전';
    }
    return '$label $rel';
  }

}
