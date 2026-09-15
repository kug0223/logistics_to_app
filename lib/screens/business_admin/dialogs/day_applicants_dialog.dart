// 지원명단 다이얼로그 — 선택 날짜의 지원자(PENDING) + 확정자(CONFIRMED)
// 공고(TO) → 업무상세별로 묶어서 표시, work_applicants_dialog 카드 스타일 준용
import 'dart:convert';
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/business_model.dart';
import '../../../models/core/employment_contract_model.dart';
import '../../../models/core/monthly_review_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_data.dart';
import '../../../models/core/business_member_model.dart';
import '../../../providers/user_provider.dart';
import '../../../screens/common/settings_screen.dart';
import '../../../screens/contract/contract_sign_screen.dart' show ContractTemplateWidget;
import '../../../services/contract_service.dart';
import '../../../services/firestore_service.dart';
import '../../../services/monthly_review_service.dart';
import '../../../utils/id_card_helper.dart';
// trust_score_helper: 신뢰도 점수 시스템 제거 (5A.2A)
import '../../../theme/app_colors.dart';
import '../../../utils/dialog_helper.dart';
import '../../../models/ui/day_staffing_row.dart';
import '../../../models/ui/invite_capacity_state.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../widgets/app_select_field.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../models/core/contract_template_model.dart' show ContractArticle;
import '../../../widgets/dialogs/contract_template_selector_dialog.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../widgets/work_type_icon.dart';
import 'available_workers_bottom_sheet.dart';
import 'invite_method_sheet.dart';
import 'invite_worker_dialog.dart';

// ─── 그룹 데이터 (업무 단위) ────────────────────────────────────────────────
class _GroupData {
  final String? toId;
  final String toTitle;
  final String workType;
  final String startTime;
  final String endTime;
  final bool isLongTerm;
  /// [8.1E.4] canonical workDetail ID (wdId, new-schema 슬롯)
  final String? wdId;
  final String? workDetailId;   // composite WorkDetail ID (레거시/capacityKey 용)
  int requiredCount;             // 나중에 채움
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
  InviteCapacityState get capacityState => inviteCapacityStateOf(
        canonicalConfirmed: canonicalConfirmed,
        requiredCount: requiredCount,
      );

  /// capacity를 알고 있고 자리가 남았다 — 이것만 `초대 중`이다.
  List<ApplicationModel> get activeInvites =>
      capacityState == InviteCapacityState.available ? invitedApps : const [];

  /// capacity를 알고 있고 자리가 찼다.
  ///
  ///   상태는 INVITED 그대로 둔다. 자리가 다시 열리면 다시 수락 가능해지는
  ///   현재 정책을 보존해야 하므로, 표시 때문에 CANCELED로 바꾸지 않는다.
  List<ApplicationModel> get staleInvites =>
      capacityState == InviteCapacityState.full ? invitedApps : const [];

  /// capacity를 모른다 — 수락 가능한지도 찼는지도 말할 수 없다.
  List<ApplicationModel> get unknownInvites =>
      capacityState == InviteCapacityState.unknown ? invitedApps : const [];

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

  const DayApplicantsDialog({
    super.key,
    required this.date,
    required this.businessIds,
    required this.businesses,
    this.filterToId,
  });

  @override
  State<DayApplicantsDialog> createState() => _DayApplicantsDialogState();
}

class _DayApplicantsDialogState extends State<DayApplicantsDialog> {
  final FirestoreService _svc = FirestoreService();
  final ContractService _contractSvc = ContractService();
  final MonthlyReviewService _reviewSvc = MonthlyReviewService();

  bool _isLoading = true;
  bool _isProcessing = false;
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
  Map<String, String?> _contractStatusMap = {};
  Map<String, int> _weeklyWorkCountMap = {};
  Map<String, int> _workDetailCapacityMap = {};

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
  final Map<String, bool> _reviewWrittenMap = {};
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

  String _bizName(String? bizId) {
    if (bizId == null) return '';
    for (final b in widget.businesses) {
      if (b.id == bizId) return b.name;
    }
    return bizId;
  }

  Future<void> _load() async {
    final bizId = _selectedBusinessId;
    if (bizId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _isLoading = true;
      _selectedIds.clear();
      _starredIds.clear();
      _idCardStatusMap = {};
      _reviewWrittenMap.clear();
      _hasWorkedMap = {}; // [BUG-CANCEL-01] 로드 시작 시 초기화 — 이전 날짜 잔류 방지
      _noShowApplicationIds = {}; // [R5.1] 초기화
      _toCache.clear();   // 파트변경 후 재로드 시 TO 캐시 무효화
      _isBatchMode = false;
      _idCardSelectGroupKey = null;
      _selectedIdCardUserIds.clear();
      _contractBatchGroupKey = null;
    });

    try {
      // Phase 1: 지원자 + 확정자 병렬 조회
      final phase1 = await Future.wait([
        _svc.getPendingApplicationsByDateAndBusiness(
            date: widget.date, businessId: bizId),
        _svc.getConfirmedWorkersByDateAndBusiness(
            date: widget.date, businessId: bizId),
      ]);
      var pending = phase1[0] as List<ApplicationModel>;
      var confirmed = phase1[1] as List<ApplicationModel>;

      // [R2] 이 날짜의 FLEX 모집 단위 — 지원서와 별개로 slot에서 읽는다.
      //   실패해도 지원자 명단은 유효하므로 전체를 ERROR로 만들지 않고,
      //   충원 영역만 UNKNOWN으로 내린다 (ERROR != ZERO).
      List<DayStaffingRow>? staffingRows;
      try {
        final (dayStart, _) = FormatHelper.kstDayRange(widget.date);
        staffingRows = await _svc.getDayStaffingDetail(
          businessId: bizId,
          dayStartMs: dayStart.millisecondsSinceEpoch,
        );
        if (widget.filterToId != null) {
          staffingRows = staffingRows
              .where((r) => r.toId == widget.filterToId)
              .toList();
        }
      } catch (e) {
        debugPrint('⚠️ [DayApplicants] 인력 현황 조회 실패: $e');
        staffingRows = null;
      }

      // [R2.2] 초대 현황 — 지원자 목록과 별개로 읽는다.
      //   실패해도 지원자 명단은 유효하므로 초대 영역만 UNKNOWN으로 내린다.
      //
      //   canManageTo가 없으면 아예 조회하지 않는다. 그 권한이 없는 관리자는
      //   초대를 보낼 수도 없고(CTA도 같은 권한으로 막혀 있다), 서버도 거부한다.
      //   권한 없음을 `확인하지 못했어요`(ERROR)로 표시하지 않기 위해
      //   빈 목록으로 둔다 — NO_PERMISSION != ERROR.
      List<ApplicationModel>? invitations = const [];
      final canSeeInvites = _canForSelectedBiz((p) => p.canManageTo);
      if (canSeeInvites) {
      try {
        invitations = await _svc.getDayInvitationsByDateAndBusiness(
            date: widget.date, businessId: bizId);
        if (widget.filterToId != null) {
          invitations =
              invitations.where((a) => a.toId == widget.filterToId).toList();
        }
      } catch (e) {
        debugPrint('⚠️ [DayApplicants] 초대 현황 조회 실패: $e');
        invitations = null;
      }
      }

      // 특정 공고 필터 (TOGroupCard 명단 보기)
      if (widget.filterToId != null) {
        pending = pending.where((a) => a.toId == widget.filterToId).toList();
        confirmed = confirmed.where((a) => a.toId == widget.filterToId).toList();
      }

      if (!mounted || _selectedBusinessId != bizId) return;

      // Phase 2: 유저 프로필 + 계약서 상태 + 주간 근무횟수 병렬 조회
      final allApps = [...pending, ...confirmed];
      Map<String, UserModel> userMap = {};
      Map<String, String?> contractMap = {};
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

        final reviewFuture = confirmedUserIds.isNotEmpty
            ? Future.wait(confirmedUserIds.map((uid) async {
                final key = MonthlyReviewModel.generateKeyForUser(
                  businessId: bizId,
                  targetUserId: uid,
                  year: widget.date.year,
                  month: widget.date.month,
                );
                final exists = await _reviewSvc.getReviewById(key);
                return MapEntry(uid, exists != null);
              }))
            : Future.value(<MapEntry<String, bool>>[]);

        final hasWorkedFuture = confirmedUserIds.isNotEmpty
            ? _svc.loadHasWorkedMap(businessId: bizId, date: widget.date)
            : Future.value(<String, bool>{});

        // [R5.1] NO_SHOW applicationId 집합 선제 시작 (Phase 2와 병렬)
        final noShowFuture = _svc.getNoShowApplicationIdsByDate(
          businessId: bizId, date: widget.date);

        // Phase 2: Phase 3 futures가 이미 실행 중인 상태에서 병렬로 처리됨
        Map<String, int> workDetailCapacityMap = {};
        final results = await Future.wait([
          _svc.getUsersBatch(allUids, businessId: bizId),
          _contractSvc.getContractStatusBatch(allAppIds, businessId: bizId),
          _loadWeeklyCount(bizId),
          _loadWorkDetailCapacities(allApps),
          // [4J.0C] 대기 중 TO 모델 선제 로드 — canApprovePending UI gate용
          _fetchToCacheForPending(pending),
        ]);
        userMap = results[0] as Map<String, UserModel>;
        contractMap = results[1] as Map<String, String?>;
        weeklyMap = results[2] as Map<String, int>;
        workDetailCapacityMap = results[3] as Map<String, int>;

        // Phase 3 결과 수집 (Phase 2와 병렬로 이미 실행 완료됐을 가능성 높음)
        final idCardMap = await idCardFuture;

        final Map<String, bool> reviewMap = {};
        reviewMap.addAll(Map.fromEntries(await reviewFuture));

        // [BUG-CANCEL-01] 당일 근무 여부 맵 — 확정취소 버튼 가드용
        final hasWorkedMap = await hasWorkedFuture;

        // [R5.1] NO_SHOW applicationId 집합 수집
        final noShowApplicationIds = await noShowFuture;

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
          _dayStaffingRows = staffingRows;
          _dayInvitations = invitations;
          _idCardStatusMap = idCardMap;
          _reviewWrittenMap.addAll(reviewMap);
          _starredIds.addAll(starredFromFirestore);
          _hasWorkedMap = hasWorkedMap; // [BUG-CANCEL-01]
          _noShowApplicationIds = noShowApplicationIds; // [R5.1]
          _isLoading = false;
          _rebuildGroups();
        });
        return;
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
        _contractStatusMap = {};
        _idCardStatusMap = {};
        _workDetailCapacityMap = {};
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
      final date = widget.date;
      final weekStart = date.subtract(Duration(days: date.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));
      final result = await _svc.getWeeklyAttendanceByBusiness(
        businessId: bizId,
        weekStart: weekStart,
        weekEnd: weekEnd,
      );
      // Map<String, List<AttendanceModel>> — key = userId
      // 실제 출근 기록만 카운트 (결근·노쇼 제외)
      return result.map((uid, list) => MapEntry(
            uid,
            list
                .where((a) =>
                    a.checkIn != null &&
                    a.status != AttendanceModel.statusAbsent &&
                    a.status != AttendanceModel.statusNoShow)
                .length,
          ));
    } catch (e) {
      debugPrint('⚠️ _loadWeeklyCount 조회 실패 (빈 맵 반환): $e');
      return {};
    }
  }

  /// 슬롯 문서의 workDetails별 requiredCount 맵 반환 (업무 단위 정원 표시용)
  Future<Map<String, int>> _loadWorkDetailCapacities(List<ApplicationModel> allApps) async {
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
      final tos = await Future.wait(toIds.map((id) => _svc.getTO(id)));
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
      final caps = await _svc.getSlotWorkDetailCapacities(e.key, e.value);
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
      final to = await _svc.getTO(id);
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
      // capacity 맵 조회는 composite key 기반 (_workDetailCapacityMap 키 포맷 유지)
      final compositeKey = app.workDetailId?.isNotEmpty == true
          ? app.workDetailId!
          : '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
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
        existing.slotId ??= row.slotId;
        // [R2.2.1] 확정 수도 slot이 진실이다 — 초대가 지금 수락될 수 있는지는
        //   근로자 화면과 같은 canonical 값으로 판정해야 한다.
        existing.canonicalConfirmed = row.confirmedCount;
        continue;
      }
      groups[key] = _GroupData(
        toId: row.toId,
        toTitle: row.toTitle,
        workType: row.workType,
        startTime: row.startTime,
        endTime: row.endTime,
        isLongTerm: false,
        wdId: row.wdId,
        requiredCount: row.requiredCount,
        slotId: row.slotId,
      )..canonicalConfirmed = row.confirmedCount;
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
          if (!_isLoading) _buildStatsStrip(context),
          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: LoadingWidget(message: '지원명단 불러오는 중...'),
                  )
                : _buildBody(context),
          ),
          if (!_isLoading && _selectedIds.isNotEmpty)
            _buildBatchActionBar(context),
          _buildBottomBar(context),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return AppModalHeader(
      title: '지원명단',
      subtitle: FormatHelper.formatDateLong(widget.date),
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
    // [R5.1] 좌석 반납된 (staffingReleasedAt != null) 확정자는 정원 계산에서 제외
    final totalShortage = _cachedGroups.fold<int>(
      0,
      (acc, g) => acc + (g.requiredCount -
          g.confirmedApps.where((a) => !a.isStaffingReleased).length).clamp(0, 99999),
    );
    final shortageColor =
        totalShortage > 0 ? AppColors.errorDark : AppColors.grey500;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.grey200)),
      ),
      child: Row(
        children: [
          _statCell(context, '부족', totalShortage, shortageColor),
          _statDivider(context),
          _statCell(context, '지원', _pendingApps.length, AppColors.warningDark),
          _statDivider(context),
          _statCell(
              context, '확정', _confirmedApps.length, AppColors.successDark),
          _statDivider(context),
          Material(
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
          ),
        ],
      ),
    );
  }

  Widget _statCell(
      BuildContext context, String label, int count, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count명',
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

  Widget _buildBody(BuildContext context) {
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
        return Padding(
          padding: const EdgeInsets.all(32),
          child: AppEmptyState(
            icon: Icons.error_outline,
            iconColor: AppColors.error,
            title: '인력 현황을 불러오지 못했어요',
            subtitle: '지원자와 부족 인원을 확인할 수 없습니다.',
            action: TextButton(
              onPressed: _load,
              child: const Text('다시 시도'),
            ),
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
    return _buildListBody(context);
  }

  Widget _buildListBody(BuildContext context) {
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
    return ListView.separated(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      itemCount: toKeys.length,
      separatorBuilder: (_, __) =>
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
      itemBuilder: (_, i) => _buildTOSection(context, byTO[toKeys[i]]!),
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
                Expanded(
                  child: Text(
                    first.toTitle.isNotEmpty ? first.toTitle : first.workType,
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 전체 통계 요약
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (totalPending > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '지원 $totalPending',
                          style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.warning)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    if (totalConfirmed > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '확정 $totalConfirmed',
                          style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.success)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
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
            decoration: BoxDecoration(
              color: AppColors.grey100,
              border: Border(
                left: BorderSide(color: AppColors.info, width: 3),
              ),
            ),
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
                      Text(
                        '${g.startTime} ~ ${g.endTime}',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey500),
                      ),
                    ],
                  ),
                ),
                // 업무별 통계 배지
                _buildGroupStats(context, g),
              ],
            ),
          ),
        ),

        // ── 대기 중 섹션 ──
        // [R4] Hierarchy: 이미 지원한 대기자를 먼저 검토 → outbound invite는 그 아래
        if (g.pendingApps.isNotEmpty) ...[
          _sectionDivider(
              context, '지원 (${g.pendingApps.length}명)', AppColors.warning),
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
        if (!g.isLongTerm && g.toId != null && g.requiredCount > 0 &&
            g.capacityState == InviteCapacityState.available &&
            g.requiredCount > g.confirmedApps.where((a) => !a.isStaffingReleased).length)
          Builder(builder: (ctx) {
            // [R2] slotId는 그룹 자신이 안다. 이전에는 지원서에서 유도해
            //   지원자가 0명인 모집 단위에서 null이 되고 CTA가 사라졌다 —
            //   충원이 가장 필요한 상태에서 충원 수단이 없어지는 경로였다.
            final slotId = g.slotId;
            if (slotId == null) return const SizedBox.shrink();
            if (!_canForSelectedBiz((p) => p.canManageTo)) {
              return const SizedBox.shrink();
            }
            return _buildInviteButton(g, slotId);
          }),

        // [R2.2.1 CORRECTION] capacity UNKNOWN — 없는 것처럼 지나가지 않는다.
        //   충원 CTA를 내린 이유를 말해 준다. `부족 0`이라서가 아니라
        //   **읽지 못해서**다 (ERROR != ZERO).
        if (!g.isLongTerm && g.toId != null && g.slotId != null &&
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
            if (requestableCount == 0) return const SizedBox.shrink();
            return _buildIdCardRequestSection(ctx, g, requestableCount);
          }),
          Builder(builder: (ctx) {
            final noContractCount = g.confirmedApps.where((app) {
              final status = _contractStatusMap[app.id];
              return status == null || status.isEmpty || status == 'voided';
            }).length;
            if (noContractCount == 0) return const SizedBox.shrink();
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
                      hasMultipleParts: hasMultipleParts))
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

  Widget _sectionDivider(BuildContext context, String label, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      child: Row(
        children: [
          Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(label,
              style: ResponsiveHelper.smallStyle(context, color: color)
                  .copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── [Phase 8.1B.3] 인력 초대 버튼 + InviteMethodSheet 라우팅 ─────────────

  Widget _buildInviteButton(_GroupData g, String slotId) {
    // [R6.1] staffingReleasedAt 좌석 제외 — invite button label/CTA strength 정합성
    final shortage = g.requiredCount -
        g.confirmedApps.where((a) => !a.isStaffingReleased).length;
    // [UX-D-03] pendingCount >= shortage: 현재 대기자 풀로 이론적 부족 충족 가능
    // → 기존 지원자 처리가 운영 우선순위이므로 CTA를 tertiary 약화로 신호.
    // PENDING을 공식 shortage/capacity에서 차감하지 않음 — 시각 강도만 조정.
    final isPendingSufficient = g.pendingApps.length >= shortage;
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
                foregroundColor: AppColors.info,
                side: const BorderSide(color: AppColors.info),
                alignment: Alignment.centerLeft,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
    );
  }

  Future<void> _openInviteMethod(_GroupData g, String slotId) async {
    if (!mounted) return;
    // [GAP-DAD-STAFFING-RELEASED-01 FIX] staffingReleased 좌석 반납 앱 제외 — stats strip과 동일 기준
    final shortage = (g.requiredCount - g.confirmedApps.where((a) => !a.isStaffingReleased).length).clamp(0, 99);

    // 1. 인력 초대 방식 선택 시트 — State.context 사용 (mounted 보장)
    final choice = await DialogHelper.showSheet<String>(
      context,
      builder: (ctx) => InviteMethodSheet(
        workType: g.workType,
        date: widget.date,
        startTime: g.startTime,
        endTime: g.endTime,
        shortage: shortage,
      ),
    );

    if (!mounted || choice == null) return;

    // 사업장명 취득
    final biz = widget.businesses.where((b) => b.id == _selectedBusinessId)
        .isNotEmpty
        ? widget.businesses.firstWhere((b) => b.id == _selectedBusinessId)
        : (widget.businesses.isNotEmpty ? widget.businesses.first : null);
    final businessName = biz?.name ?? '';

    if (choice == 'availability') {
      // 2a. 근무 가능 인력 시트
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
          confirmedCount: g.confirmedApps.length,
        ),
      );
    } else if (choice == 'direct') {
      // 2b. 직접 초대 다이얼로그 (contextual mode — 날짜·슬롯 재선택 없음)
      if (!mounted) return;
      await showDialog<void>(
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
        ),
      );
    }
  }

  // ── Applicant Card ─────────────────────────────────────────────────────────

  Widget _buildApplicantCard(BuildContext context, ApplicationModel app,
      {required bool isPending, bool isGroupIdCardMode = false, int index = 0, bool hasMultipleParts = false}) {
    final user = _userMap[app.uid];
    final isSelected = _selectedIds.contains(app.id);
    final isStarred = isPending && _starredIds.contains(app.id);
    final idCardStatus = _idCardStatusMap[user?.uid ?? ''] ?? 'none';
    final canManageTo = _canForSelectedBiz((p) => p.canManageTo);
    final canManageContract = _canForSelectedBiz((p) => p.canManageContract);

    final Color cardBg;
    final Color cardBorder;
    final double borderWidth;
    if (isSelected) {
      cardBg = AppColors.warningBg;
      cardBorder = AppColors.warning;
      borderWidth = 1.5;
    } else if (isStarred) {
      cardBg = AppColors.amber.withValues(alpha: 0.1);
      cardBorder = AppColors.amberLight;
      borderWidth = 1.0;
    } else if (!isPending) {
      cardBg = AppColors.successBg.withValues(alpha: 0.35);
      cardBorder = AppColors.successLight.withValues(alpha: 0.7);
      borderWidth = 1.0;
    } else {
      cardBg = Colors.white;
      cardBorder = AppColors.grey200;
      borderWidth = 1.0;
    }

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
      child: Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 4)),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cardBorder, width: borderWidth),
        ),
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
                            activeColor: AppColors.info,
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
                      if (_genderAge(user).isNotEmpty) ...[
                        const SizedBox(width: 3),
                        Text(_genderAge(user),
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey500)),
                      ],
                    ],
                  ),
                ),
                Text(
                  _timeAgo(app.appliedAt),
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey400),
                ),
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

            // ── Row 2: 정보 (신뢰점수·전화·주간횟수·별점) ──
            const SizedBox(height: 4),
            Wrap(
              spacing: 5,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
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
                if (!isPending) _buildReviewBadge(context, user?.uid),
                _contractBadge(context, app.id, isPending: isPending),
                if (!isPending)
                  IdCardHelper.buildStatusBadge(context, idCardStatus),
              ],
            ),

            // ── Row 4: 액션 버튼 ──
            // [4J.0C] 거절: 항상 허용(PENDING 정리), 승인: canApprovePending만 허용 — WorkApplicants parity
            // _toCache에 TO가 없으면 true(낙관적 허용) — CF가 최종 gate
            if (isPending && !_isBatchMode && canManageTo) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _actionButton(
                    context,
                    label: '거절',
                    color: AppColors.error,
                    onTap: () => _rejectApp(app),
                  ),
                  if (_toCache[app.toId]?.canApprovePending ?? true) ...[
                    const SizedBox(width: 8),
                    _actionButton(
                      context,
                      label: '확정',
                      color: AppColors.success,
                      filled: true,
                      onTap: () => _approveApp(app),
                    ),
                  ],
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
              if ((((_contractStatusMap[app.id] == null ||
                          _contractStatusMap[app.id]!.isEmpty ||
                          _contractStatusMap[app.id] == 'voided') &&
                      canManageContract) ||
                  (_canCancelConfirmation(app) && canManageTo) ||
                  (app.toId != null && hasMultipleParts && canManageTo) ||
                  // [R5.1] NO_SHOW + 미반납 + 단기 + 권한 있을 때 버튼 표시
                  (_noShowApplicationIds.contains(app.id) && !app.isStaffingReleased &&
                      !app.isLongTermApplication && canManageTo))) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // [R5.1] 대체 인력 충원 버튼 — NO_SHOW 확인 후 미반납 상태에서만 표시
                    if (_noShowApplicationIds.contains(app.id) &&
                        !app.isStaffingReleased &&
                        !app.isLongTermApplication &&
                        canManageTo) ...[
                      _actionButton(
                        context,
                        label: '대체 인력 충원',
                        color: AppColors.warning,
                        filled: true,
                        onTap: () => _releaseNoshowSeat(app),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // 계약 미작성 시 개별 계약서 작성 버튼
                    if ((_contractStatusMap[app.id] == null ||
                        _contractStatusMap[app.id]!.isEmpty ||
                        _contractStatusMap[app.id] == 'voided') &&
                        canManageContract) ...[
                      _actionButton(
                        context,
                        label: '계약서 작성',
                        color: AppColors.success,
                        filled: true,
                        onTap: () => _createContractForOne(app),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // [BUG-CANCEL-01] 근무 완료·장기계약 시작 후에는 확정취소 버튼 숨김
                    if (_canCancelConfirmation(app) && canManageTo) ...[
                      _actionButton(
                        context,
                        label: '확정취소',
                        color: AppColors.error,
                        onTap: () => _cancelConfirmation(app),
                      ),
                      if (app.toId != null && hasMultipleParts) const SizedBox(width: 8),
                    ],
                    // 파트변경 버튼 — TO 소속이고 다른 파트가 있는 경우에만 표시
                    if (app.toId != null && hasMultipleParts && canManageTo)
                      _actionButton(
                        context,
                        label: '파트변경',
                        color: AppColors.info,
                        onTap: () => _showChangeWorkPartDialog(app, _userMap[app.uid]),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required String label,
    required Color color,
    bool filled = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isProcessing ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.7)),
        ),
        child: Text(
          label,
          style: ResponsiveHelper.smallStyle(
                  context, color: filled ? Colors.white : color)
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
    if (count == 0) {
      color = AppColors.grey500;
      bgColor = AppColors.grey100;
      icon = Icons.calendar_today_outlined;
    } else if (count <= 2) {
      color = AppColors.successDark;
      bgColor = AppColors.successBg;
      icon = Icons.calendar_today;
    } else if (count <= 4) {
      color = AppColors.infoDark;
      bgColor = AppColors.infoBg;
      icon = Icons.calendar_today;
    } else {
      color = AppColors.warningDark;
      bgColor = AppColors.warningBg;
      icon = Icons.calendar_today;
    }
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

  Widget _contractBadge(BuildContext context, String appId,
      {bool isPending = false}) {
    final status = _contractStatusMap[appId];
    if (status == null || status.isEmpty) {
      if (!isPending) {
        return _iconChip(context,
            icon: Icons.assignment_late_outlined,
            label: '계약미작성',
            color: AppColors.error);
      }
      return const SizedBox.shrink();
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
      case 'completed':
        return _chip(context,
            label: '계약완료',
            color: AppColors.successDark,
            bgColor: AppColors.successDark.withValues(alpha: 0.1));
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: color)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewBadge(BuildContext context, String? uid) {
    if (uid == null || !_reviewWrittenMap.containsKey(uid)) {
      return const SizedBox.shrink();
    }
    final written = _reviewWrittenMap[uid]!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: written
            ? AppColors.successDark.withValues(alpha: 0.12)
            : AppColors.warningDark.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            written ? Icons.rate_review : Icons.rate_review_outlined,
            size: ResponsiveHelper.iconSize(context, 10),
            color: written ? AppColors.successDark : AppColors.warningDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 2)),
          Text(
            written ? '리뷰완료' : '리뷰미작성',
            style: ResponsiveHelper.tinyStyle(
              context,
              color: written ? AppColors.successDark : AppColors.warningDark,
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
    final confirmed = g.confirmedApps.where((a) => !a.isStaffingReleased).length;
    final pending = g.pendingApps.length;
    final required = g.requiredCount;
    final isFull = required > 0 && confirmed >= required;
    final statusColor = isFull ? AppColors.successDark : AppColors.infoDark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isFull ? Icons.check_circle : Icons.people_outline,
          size: ResponsiveHelper.iconSize(context, 14),
          color: statusColor,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Text(
          required > 0 ? '$confirmed/$required명' : '$confirmed명',
          style: ResponsiveHelper.smallStyle(context, color: statusColor)
              .copyWith(fontWeight: FontWeight.bold),
        ),
        // [SYSTEM-INTEGRATION-R2.2] 지원 대기와 초대 중을 합치지 않는다.
        //   `대기 N명` 하나로 보여주면 관리자는 그중 몇이 자기가 보낸 초대이고
        //   몇이 들어온 지원인지 모른다 — 더 초대해야 하는지 판단할 수 없다.
        if (pending > 0) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Icon(
            Icons.schedule,
            size: ResponsiveHelper.iconSize(context, 12),
            color: AppColors.warningDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 2)),
          Text(
            '지원 $pending',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ],
        // [SYSTEM-INTEGRATION-R2.2.1] `초대 N` = INVITED **이면서 지금 수락될 수
        //   있는** 초대. 자리가 이미 찬 초대를 여기 세면 관리자는 아직 응답을
        //   기다리는 중이라고 읽고, 오지 않을 수락을 기다린다.
        //   별도 inviteCount 필드를 만들지 않는다 — Application + 현재 capacity로 센다.
        if (g.activeInvites.isNotEmpty) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Icon(
            Icons.send_outlined,
            size: ResponsiveHelper.iconSize(context, 12),
            color: AppColors.infoDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 2)),
          Text(
            '초대 ${g.activeInvites.length}',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ],
        // [R2.2.1 CORRECTION] capacity를 모르는 초대를 요약에서 지우지 않는다.
        //   숫자를 세지 않을 뿐, 초대가 떠 있다는 사실은 사실이다.
        //   숫자로 세면 `초대 중`이라고 단정하는 것이 되므로 `?`로 둔다.
        if (g.unknownInvites.isNotEmpty) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Icon(
            Icons.help_outline,
            size: ResponsiveHelper.iconSize(context, 12),
            color: AppColors.grey500,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 2)),
          Text(
            '초대 ?',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ],
    );
  }

  /// [R2.2.1 CORRECTION] 인력 현황을 읽지 못했을 때 충원 CTA 자리에 서는 안내.
  ///
  ///   CTA가 사라진 이유가 `부족 0`이 아니라 `읽지 못함`임을 말한다.
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
            child: Text(
              '인력 현황을 확인하지 못해 충원이 필요한지 알 수 없어요.\n새로고침 후 다시 확인해 주세요.',
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
  }) {
    switch (app.status) {
      case AppStatus.invited:
        // [R2.2.1 CORRECTION] 세 갈래를 각각 말한다. capacity를 모르면
        //   `초대 중`도 `모집 완료`도 사실이 아니다 — 모르는 것이다.
        switch (capacity) {
          case InviteCapacityState.available:
            return ('초대 중', AppColors.infoDark);
          case InviteCapacityState.full:
            return ('모집 완료 · 수락 불가', AppColors.grey600);
          case InviteCapacityState.unknown:
            return ('상태 확인 불가', AppColors.grey500);
        }
      case AppStatus.confirmed:
      case AppStatus.contractPending:
        // invitedAt이 있어 이 목록에 들어왔다 — 관리자 초대를 근로자가 수락했다.
        return ('초대 수락 · 확정', AppColors.successDark);
      case AppStatus.rejected:
        // invitedAt이 있으므로 근로자가 스스로 거절한 초대다.
        return ('초대 거절', AppColors.grey600);
      case AppStatus.canceled:
        return ('초대 철회', AppColors.grey600);
      case AppStatus.expired:
        return ('응답 만료', AppColors.grey600);
      case AppStatus.autoCanceled:
        return (
          app.cancelReason == 'SCHEDULE_CONFLICT' ? '일정 겹침 종료' : '자동 종료',
          AppColors.grey600,
        );
      default:
        return (app.status, AppColors.grey600);
    }
  }

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
            Text(
              '초대 현황을 확인하지 못했어요',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.errorDark),
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
    final unknown = g.unknownInvites;

    // 끝난 초대는 최근 3건만 — 기록 전체를 운영 화면에 펼치지 않는다.
    //   수락도 초대의 결과다. 확정 명단에만 두면 그 확정이 초대에서 왔다는
    //   사실이 사라진다(§5 provenance).
    final closed = [...g.closedInvites, ...g.acceptedInvites]
      ..sort((a, b) => (b.invitedAt ?? b.appliedAt).compareTo(a.invitedAt ?? a.appliedAt));
    final recentClosed = closed.take(3).toList();
    if (outstanding.isEmpty && stale.isEmpty && unknown.isEmpty &&
        recentClosed.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (outstanding.isNotEmpty) ...[
          _sectionDivider(context, '초대 중 (${outstanding.length}명)', AppColors.infoDark),
          ...outstanding.map((a) => _buildInviteRow(context, a,
              capacity: InviteCapacityState.available)),
        ],
        if (stale.isNotEmpty) ...[
          _sectionDivider(
              context, '모집 완료 · 수락 불가 (${stale.length}명)', AppColors.grey500),
          ...stale.map((a) =>
              _buildInviteRow(context, a, capacity: InviteCapacityState.full)),
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
    return Padding(
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
          Container(
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
        ],
      ),
    );
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
        color: isActive ? AppColors.infoBg : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? AppColors.info : AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.badge,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.info),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              isActive
                  ? '${_selectedIdCardUserIds.length}명 선택됨'
                  : '미요청 $requestableCount명',
              style:
                  ResponsiveHelper.bodyStyle(context, color: AppColors.infoDark),
            ),
          ),
          if (isActive && _selectedIdCardUserIds.isNotEmpty) ...[
            InkWell(
              onTap: _batchRequestIdCard,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('요청하기',
                    style: ResponsiveHelper.smallStyle(context,
                            color: Colors.white)
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          ],
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
                color: isActive ? AppColors.grey100 : AppColors.info,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isActive ? '취소' : '신분증 요청',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: isActive ? AppColors.grey700 : Colors.white,
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
      child: Row(
        children: [
          Icon(Icons.description_outlined,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.success),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '계약서 미작성 $noContractCount명',
              style: ResponsiveHelper.bodyStyle(context,
                  color: AppColors.successDark),
            ),
          ),
          if (isProcessing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            InkWell(
              onTap: () => _batchCreateContracts(g),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '계약서 일괄작성',
                  style: ResponsiveHelper.smallStyle(context, color: Colors.white)
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
      final status = _contractStatusMap[app.id];
      return status == null || status.isEmpty || status == 'voided';
    }).toList();
    if (toProcess.isEmpty) return;

    setState(() => _contractBatchGroupKey = g.groupKey);
    try {
      List<ContractArticle>? articles;
      String sealBase64 = '';
      String sealType = 'stamp';
      WorkDetailData? workDetail;

      // 1. 템플릿 선택
      articles =
          await ContractTemplateSelectorDialog.show(context, businessId: bizId);
      if (articles == null || !mounted) return;

      // 2. 인감 확인 — SubAdmin은 사업주(ownerId) 문서에서 날인 조회
      final sealUid = up.isSubAdmin ? business.ownerId : (up.currentUser?.uid ?? '');
      if (sealUid.isNotEmpty) {
        final sealDoc = await FirebaseFirestore.instance.collection('users').doc(sealUid).get();
        if (!mounted) return;
        sealBase64 = sealDoc.data()?['sealBase64'] ?? '';
        sealType = sealDoc.data()?['sealType'] ?? 'stamp';
      }
      if (sealBase64.isEmpty) {
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
        final to = await _svc.getTO(g.toId!);
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

      // 6. 일괄 계약서 생성 + 날인
      final sealBytes = base64Decode(sealBase64);
      final finalWorkDetail = workDetail;

      Future<bool> processOne(ApplicationModel app) async {
        final user = _userMap[app.uid];
        if (user == null) return false;
        try {
          final contract = await ContractService().findOrCreateContract(
            application: app,
            business: business,
            worker: user,
            workDetail: finalWorkDetail,
            articles: articles!,
          );
          await ContractService().saveEmployerSignature(
            contract: contract,
            signatureBytes: sealBytes,
          );
          return true;
        } catch (e) {
          debugPrint('❌ [${app.id}] 계약서 발송 실패: $e');
          return false;
        }
      }

      const batchSize = 5;
      int successCount = 0;
      final List<ApplicationModel> successApps = [];
      for (var i = 0; i < toProcess.length; i += batchSize) {
        final batch =
            toProcess.sublist(i, min(i + batchSize, toProcess.length));
        final results = await Future.wait(batch.map(processOne));
        if (!mounted) return;
        for (var j = 0; j < batch.length; j++) {
          if (results[j]) {
            successCount++;
            successApps.add(batch[j]);
          }
        }
      }

      if (!mounted) return;
      if (successCount < toProcess.length) {
        ToastHelper.showWarning(
            '$successCount/${toProcess.length}명 계약서 발송 완료. 실패한 항목은 다시 시도해주세요.');
      } else {
        ToastHelper.showSuccess('${toProcess.length}명에게 계약서가 발송되었습니다');
      }
      if (successCount > 0) {
        _hasChanges = true;
        setState(() {
          for (final app in successApps) {
            _contractStatusMap[app.id] = 'pending_worker';
          }
        });
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
    required String sealBase64,
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
              color: AppColors.info.withValues(alpha: 0.08),
              child: Text(
                '아래 조건으로 선택된 $count명에게 계약서가 발송됩니다.\n이름·생년월일 등 개인정보는 각 근무자별로 적용됩니다.',
                style: ResponsiveHelper.smallStyle(ctx, color: AppColors.info),
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
                  employerSignatureUrl: contract.employerSignatureUrl,
                  employerSealBase64: sealBase64,
                  employerSealType: sealType,
                  workerSignatureUrl: contract.workerSignatureUrl,
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

  /// 파트변경 다이얼로그 (TO 소속 확정자 전용)
  Future<void> _showChangeWorkPartDialog(ApplicationModel app, UserModel? user) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // TO 및 workDetails 로드 (캐시 우선 — 재탭 시 서버 읽기 생략)
    final toId = app.toId!;
    final to = _toCache[toId] ?? await _svc.getTO(toId);
    if (!mounted) return;
    if (to == null || to.workDetails.isEmpty) {
      setState(() => _isProcessing = false);
      ToastHelper.showError('공고 정보를 불러올 수 없습니다.');
      return;
    }
    _toCache[toId] = to;
    final workDetails = to.workDetails;

    // 현재 파트 식별 (workDetailId 우선, 없으면 selectedWorkType 폴백)
    final idx = workDetails.indexWhere(
      (w) => w.id == app.workDetailId || w.workType == app.selectedWorkType,
    );
    final currentWork = idx >= 0 ? workDetails[idx] : null;

    // 현재 파트 제외한 다른 파트 목록
    final otherWorkDetails = currentWork != null
        ? workDetails.where((w) => w.id != currentWork.id).toList()
        : List<WorkDetailData>.from(workDetails);

    if (otherWorkDetails.isEmpty) {
      setState(() => _isProcessing = false);
      ToastHelper.showWarning('변경 가능한 다른 파트가 없습니다.');
      return;
    }

    // [C-1] 파트변경 전 급여 상태 확인 — confirmed: 완전 차단 / calculated: 경고 후 선택
    final int confirmedCount;
    final int calculatedCount;
    try {
      final wageCountResult = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetWageStatusCount')
          .call({'applicationId': app.id, 'businessId': app.businessId});
      final resultMap = wageCountResult.data as Map;
      confirmedCount  = resultMap['confirmedCount']  as int? ?? 0;
      calculatedCount = resultMap['calculatedCount'] as int? ?? 0;
    } catch (e) {
      debugPrint('❌ 급여 상태 확인 실패: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ToastHelper.showError('급여 상태 확인 중 오류가 발생했습니다. 다시 시도해주세요.');
      }
      return;
    }
    if (!mounted) return;

    if (confirmedCount > 0) {
      setState(() => _isProcessing = false);
      await DialogHelper.showError(
        context,
        title: '파트변경 불가',
        message: '마감 처리된 급여가 $confirmedCount건 있습니다.\n먼저 마감을 취소한 후 다시 시도해주세요.',
      );
      return;
    }

    if (calculatedCount > 0) {
      final proceed = await DialogHelper.showConfirm(
        context,
        title: '임금 계산 초기화 안내',
        message: '계산된 급여 $calculatedCount건이 있습니다.\n파트변경 시 해당 급여가 초기화되어 재계산이 필요합니다.\n계속하시겠습니까?',
        confirmText: '계속',
        cancelText: '취소',
      );
      if (proceed != true || !mounted) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
    }

    final selectedWorkId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StyledDialog(
        title: '파트변경',
        icon: Icons.swap_horiz,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${user?.name ?? '지원자'}님의 파트를 변경합니다.',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            if (currentWork != null)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 8),
                ),
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
                ),
                child: Row(
                  children: [
                    Text('현재: ', style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
                    Text(
                      currentWork.workType,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '변경할 파트 선택',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            ...otherWorkDetails.map((work) => Padding(
              padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    final confirmed = await DialogHelper.showConfirm(
                      context,
                      title: '파트 변경',
                      message: '${user?.name ?? '지원자'}님을\n'
                          '${currentWork?.workType ?? app.selectedWorkType} → ${work.workType}(으)로\n'
                          '변경하시겠습니까?',
                      confirmText: '변경',
                    );
                    if (confirmed == true && context.mounted) {
                      Navigator.pop(context, work.id);
                    }
                  },
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 12),
                      vertical: ResponsiveHelper.spacing(context, 10),
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                    ),
                    child: Row(
                      children: [
                        WorkTypeIcon.buildWithBackground(
                          iconString: work.workTypeIcon,
                          backgroundColor: work.workTypeBackgroundColor,
                          size: ResponsiveHelper.iconSize(context, 18),
                          containerSize: ResponsiveHelper.spacing(context, 32),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                work.workType,
                                style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${work.startTime}~${work.endTime} | ${work.formattedWage}',
                                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios, size: ResponsiveHelper.iconSize(context, 12), color: AppColors.grey300),
                      ],
                    ),
                  ),
                ),
              ),
            )),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );

    if (selectedWorkId == null || !mounted) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid ?? 'UNKNOWN';
      final selectedWork = otherWorkDetails.firstWhere(
        (w) => w.id == selectedWorkId,
        orElse: () => throw StateError('선택한 파트를 찾을 수 없습니다'),
      );
      await _svc.changeApplicationWorkType(
        applicationId: app.id,
        newWorkType: selectedWork.workType,
        newWage: selectedWork.wage,
        adminUID: adminUID,
        newWorkDetailId: selectedWork.id,
        newWageType: selectedWork.wageType,
        newWorkTypeIcon: selectedWork.workTypeIcon,
        newWorkTypeColor: selectedWork.workTypeColor,
        newWorkTypeBackgroundColor: selectedWork.workTypeBackgroundColor,
      );
      final resetMsg = calculatedCount > 0
          ? '\n계산된 급여 $calculatedCount건이 초기화되었습니다.'
          : '';
      if (!mounted) return;
      ToastHelper.showSuccess(
        '${user?.name ?? '지원자'}님의 파트가 ${selectedWork.workType}(으)로 변경되었습니다$resetMsg',
      );
      await _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('파트 변경에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _cancelConfirmation(ApplicationModel app) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final user = _userMap[app.uid];
      // [BUG-FIX-2] 확정 취소 사유 수집 + cancelConfirmedApplication으로 교체
      //   work_applicants_dialog과 동일 패턴 적용 (cancelReason 감사 이력 기록)
      final reason = await DialogHelper.showRejectReasonPicker(
        context,
        title: '확정 취소',
        targetName: user?.name,
        message: '취소 사유를 선택해 주세요.',
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

  Future<void> _releaseNoshowSeat(ApplicationModel app) async {
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

  Future<void> _createContractForOne(ApplicationModel app) async {
    if (_isProcessing) return;
    final bizId = _selectedBusinessId ?? '';
    if (bizId.isEmpty || widget.businesses.isEmpty) return;
    // [특이사항] orElse 폴백 제거 — 잘못된 bizId 시 첫 번째 사업장 명의로 계약서가 생성되는 것을 방지.
    final bizIdx = widget.businesses.indexWhere((b) => b.id == bizId);
    if (bizIdx < 0) return;
    final business = widget.businesses[bizIdx];
    final user = _userMap[app.uid];
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

    // 2. 인감 확인 — SubAdmin은 사업주(ownerId) 문서에서 날인 조회
    final up = context.read<UserProvider>();
    final sealUid = up.isSubAdmin ? business.ownerId : (up.currentUser?.uid ?? '');
    String sealBase64 = '';
    String sealType = 'stamp';
    if (sealUid.isNotEmpty) {
      final sealDoc = await FirebaseFirestore.instance.collection('users').doc(sealUid).get();
      if (!mounted) {
        setState(() => _isProcessing = false);
        return;
      }
      sealBase64 = sealDoc.data()?['sealBase64'] ?? '';
      sealType = sealDoc.data()?['sealType'] ?? 'stamp';
    }
    if (sealBase64.isEmpty) {
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
    final toId = group?.toId;
    final groupWorkType = group?.workType;
    final groupStartTime = group?.startTime;
    final groupEndTime = group?.endTime;
    if (toId != null) {
      setState(() => _isProcessing = true);
      try {
        final to = await _svc.getTO(toId);
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
      final sealBytes = base64Decode(sealBase64);
      final contract = await ContractService().findOrCreateContract(
        application: app,
        business: business,
        worker: user,
        workDetail: workDetail,
        articles: articles,
      );
      await ContractService().saveEmployerSignature(
        contract: contract,
        signatureBytes: sealBytes,
      );
      if (!mounted) return;
      ToastHelper.showSuccess('계약서가 발송되었습니다');
      _hasChanges = true;
      setState(() => _contractStatusMap[app.id] = 'pending_worker');
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
          Icon(Icons.check_circle_rounded, size: 14, color: brand),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text('${_selectedIds.length}명 선택',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold, color: brand)),
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
            '$name을(를) 계약 대기 상태로 변경하시겠습니까?\n이후 계약서를 직접 작성·서명해야 합니다.',
        confirmText: '확정',
      );
      if (!ok || !mounted) return;
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      await _svc.updateApplicationStatus(
        applicationId: app.id,
        // [P1-A-FIX] contractPending 직접 write 제거 → confirmed CF 경유 필수
        // updateApplicationStatus(confirmed) → _confirmWithConflictCheck() → callableConfirmApplication
        // CF가 TOCTOU 잠금·충돌감지·계약서 생성 후 CONTRACT_PENDING 상태로 설정
        status: AppStatus.confirmed,
        confirmedBy: adminUID,
      );
      _hasChanges = true;
      if (!mounted) return;
      ToastHelper.showSuccess('확정되었습니다. 계약서를 작성해 주세요.');  // [4J.0C] CONTRACT_PENDING 결과 — WorkApplicants parity
      await _load();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ToastHelper.showError(e.message ?? '확정 처리 중 오류가 발생했습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('확정 처리 중 오류가 발생했습니다');
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
            '선택한 $count명을 계약 대기 상태로 변경하시겠습니까?\n이후 각 지원자의 계약서를 직접 작성·서명해야 합니다.',
        confirmText: '일괄 확정',
      );
      if (!confirmed || !mounted) return;
      final ids = _selectedIds.toList();
      final total = ids.length; // [4J.1] 부분 실패 카운트 계산용
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      // [P1-A-FIX] parallel Future.wait → sequential for-loop
      //   confirmed CF 경유: callableConfirmApplication은 Firestore 트랜잭션 내 충돌감지 수행.
      //   병렬 처리 시 CF 간 레이스컨디션으로 동일 슬롯 중복 확정 가능 → 순차 처리 필수.
      //   [보안] PERMISSION_DENIED 포함 실패 로그 유지 — 크로스-사업장 접근 감지용.
      int successCount = 0;
      for (final appId in ids) {
        try {
          await _svc.updateApplicationStatus(
            applicationId: appId,
            // confirmed → _confirmWithConflictCheck() → CF callableConfirmApplication
            // CF가 TOCTOU 잠금·충돌감지·계약서 생성 후 CONTRACT_PENDING 설정
            status: AppStatus.confirmed,
            confirmedBy: adminUID,
          );
          successCount++;
        } catch (e) {
          debugPrint('❌ [_batchApprove] 확정 실패 [$appId]: $e');
        }
      }
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
      await _load();
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

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.isNegative) return '방금 전';
    if (diff.inDays >= 1) return '${diff.inDays}일 전';
    if (diff.inHours >= 1) return '${diff.inHours}시간 전';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}분 전';
    return '방금 전';
  }

}
