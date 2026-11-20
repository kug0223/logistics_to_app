import 'dart:math' show max;
import 'job_posting_reads.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';

// Models
import '../../models/core/business_model.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_model.dart';
import '../../models/core/business_work_type_model.dart';
import '../../models/core/insurance_rate_model.dart';
// TaxDeductionBadge 임포트 제거 — 업무카드에서 인라인 텍스트로 대체;

// Services
import '../../services/firestore_service.dart';
import '../../services/tax_identity_service.dart';
import '../../services/work_type_guide_resolver.dart';

// Models (slot, application)
import '../../models/core/slot_model.dart';
import '../../models/core/application_model.dart';

// Utils
import '../../utils/attendance_policy_disclosure.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/image_helper.dart';
import '../../utils/dialog_helper.dart';

// Widgets
import '../../widgets/common/attendance_rule_guide_view.dart';
import '../../widgets/common/common_widgets.dart';
import '../../utils/text_layout.dart';
import '../../widgets/common/loading_widget.dart';
// WorkTypeIcon import removed — 업무카드 placeholder 아이콘 제거 (spec 요구)
import '../../widgets/maps/kakao_map_widget.dart';
import '../../widgets/common/defer_until_on_screen.dart';
import '../../widgets/maps/full_map_dialog.dart';
import '../../widgets/dialogs/apply/application_relation.dart';
import '../../widgets/dialogs/apply/commitment_conflict.dart';
import '../../widgets/dialogs/apply/multi_apply_confirm_sheet.dart';
import '../../widgets/dialogs/apply/longterm_apply_sheet.dart';
import '../../widgets/dialogs/apply/apply_summary_section.dart';
import '../../widgets/dialogs/apply/document_access_consent.dart';
import '../../theme/app_colors.dart';
import '../../theme/concept_tokens.dart';
import '../user/apply_prerequisites_screen.dart';
import 'document_management_screen.dart';
// ── 내 지원 진입 전용 ─────────────────────────────────────────────────────────
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/core/employment_contract_model.dart';
import '../contract/contract_sign_screen.dart';
// [CROSS-DOMAIN-R5.3D] 통합 초대 상세 — promise / context / acceptability 분리
import '../../models/ui/invitation_projection.dart';
import '../../models/ui/work_capacity_reading.dart';
import '../../widgets/user/invitation_promise_card.dart';

enum TODetailMode {
  applicant,
  adminPreview,
}

class JobPostingScreen extends StatefulWidget {
  final String? toId;
  final TOModel? to;
  final List<WorkDetailModel>? workDetails;
  final BusinessModel? business;
  final TODetailMode mode;
  final DateTime? slotDate;
  final int? slotTotalRequired;
  final int? slotConfirmedCount;
  final int? slotPendingCount;
  final Map<String, Map<String, int>>? workDetailStats;

  /// 내 지원 화면에서 진입할 때 전달. null이면 일자리 찾기 진입(기존 동작).
  final ApplicationModel? myApplication;

  /// [R7-P2-2 후속 P22-D] 재조회 경계. production 은 null.
  final JobPostingReads? reads;

  /// CONTRACT_PENDING 상태의 계약서 정보. myApplication과 함께 사용.
  final EmploymentContractModel? myContract;

  const JobPostingScreen({
    super.key,
    this.toId,
    this.to,
    this.workDetails,
    this.business,
    this.mode = TODetailMode.applicant,
    this.slotDate,
    this.slotTotalRequired,
    this.slotConfirmedCount,
    this.slotPendingCount,
    this.workDetailStats,
    this.myApplication,
    this.reads,
    this.myContract,
  }) : assert(toId != null || to != null || myApplication != null,
            // [R5.3D] 공고를 특정할 수 없어도 초대 자체는 열 수 있어야 한다 —
            //   약속은 Application에 있고, 공고는 설명일 뿐이다.
            'toId / to / myApplication 중 하나는 필수입니다');

  @override
  State<JobPostingScreen> createState() => _JobPostingScreenState();
}

class _JobPostingScreenState extends State<JobPostingScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late final JobPostingReads _reads =
      widget.reads ?? JobPostingReads.of(_firestoreService);
  UserProvider? _userProvider;

  bool _isLoading = true;
  TOModel? _to;
  BusinessModel? _business;
  List<WorkDetailModel> _workDetails = [];
  /// [WORKTYPE-IDENTITY] 업무 안내 원천(비활성 포함). 근무와의 연결은 WorkTypeGuideResolver 만 정한다.
  WorkTypeCatalog _workTypeCatalog = WorkTypeCatalog.empty;

  SlotModel? _slot;
  List<SlotModel> _allSlots = [];

  /// [POSTING-V2-03C.1] 근무일 목록을 **완전하게** 확보하지 못했다.
  ///
  /// 501+ 근무일이라 잘린 목록만 받은 경우다. `_allSlots`를 비우는 것만으로는
  /// "근무일이 실제로 0개"인 상태와 구분되지 않아 '선택 가능한 근무 날짜가
  /// 없습니다'로 보인다 — ERROR != ZERO 위반이다. 별도 상태로 갈라 놓는다.
  bool _slotLoadError = false;

  /// [SYSTEM-INTEGRATION-POSTING-1] 공고를 못 읽었다(≠ 없다).
  /// 이 구분이 없으면 네트워크 실패가 '공고를 찾을 수 없습니다'로 보인다.
  bool _loadFailed = false;
  List<ApplicationModel> _myApplications = [];
  String? _applicantUid;

  String? _applyBlockReason;
  bool get _isApplyable => _applyBlockReason == null;
  bool _isApplying = false;
  int _memCacheWidth = 800;

  // ── 내 지원 진입 시 액션 상태 ──────────────────────────────────────────────
  bool _isCancellingApplication = false;
  bool _isContractSignOpening   = false;
  bool _isAcceptingInvite       = false;
  bool _isDecliningInvite       = false;

  // 갤러리
  int _galleryPage = 0;
  final PageController _galleryController = PageController();

  // 날짜 선택
  DateTime? _selectedSlotDate;

  // 업무 선택 상태
  // flex TO: 'yyyy-MM-dd' → workDetailId (날짜당 1개)
  final Map<String, String> _flexSelected = {};
  // contract TO: workDetailId Set (여러 개 선택 가능)
  final Set<String> _contractSelected = {};

  // ── Computed ──────────────────────────────────

  // 사업장 갤러리 이미지 — 대표이미지 + 추가 사업장 이미지 (업무/교통 이미지 제외)
  // 대표이미지(mainImageUrl) → 추가이미지(imageUrls) 순서로 구성
  List<String> get _galleryImages {
    final images = <String>[];
    if (_business?.mainImageUrl != null) images.add(_business!.mainImageUrl!);
    if (_business?.imageUrls != null) images.addAll(_business!.imageUrls!);
    return images;
  }

  List<WorkDetailModel> get _currentWorkDetails {
    if (!(_to?.isFlexType ?? false)) return _workDetails;
    return _currentSlot?.workDetails ?? _workDetails;
  }

  SlotModel? get _currentSlot {
    if (_selectedSlotDate == null) return _slot;
    return _allSlots.where((s) =>
      s.date.year == _selectedSlotDate!.year &&
      s.date.month == _selectedSlotDate!.month &&
      s.date.day == _selectedSlotDate!.day
    ).firstOrNull;
  }

  // ── [R7-P4.4E.7A] 지원 관계 — 판정은 공용 resolver 하나로 ────────────
  //
  //   이 화면은 `_myApplications` 를 이미 들고 있으면서도 선택 가능 여부를
  //   그것과 무관하게 정했다. 그래서 이미 지원한 업무에도 `선택` 이 보이고,
  //   누르면 선택 집합에 들어가 CTA 의 N 을 부풀렸다. 사용자는 확인 시트에
  //   들어간 뒤에야 이미 지원한 건임을 알았다.
  //
  //   확인 시트·서버와 **같은** 판정을 쓴다. 새 reader 도 새 identity 도
  //   만들지 않는다 — `_myApplications` + `ApplicationRelationResolver`.

  /// [R7-APPLICATION-LIFECYCLE.1C] 내 지원 목록을 **읽지 못했다.**
  ///
  ///   예전에는 이 읽기가 실패하면 `Future.wait` 전체가 깨져 공고 자체를
  ///   못 보여줬다. 이제 공고는 보여주고, 겹침 판정만 `unknown` 으로 둔다 —
  ///   못 읽은 것을 "겹치는 약속이 없다" 로 바꾸지 않고, 화면이 그 사실을
  ///   말한다(제출 직전 확인 시트가 서버 경유로 한 번 더 본다).
  bool _myApplicationsFailed = false;

  // ignore: prefer_void_to_null — Future<Null>.catchError 의 handler 계약이다.
  Null _onMyApplicationsFailed(Object e) {
    debugPrint('⚠️ 내 지원 목록 로드 실패: $e');
    _myApplicationsFailed = true;
    return null;
  }

  /// 이 근무에 지금 어떤 관계가 있는가. `none` 이면 신규 지원 후보다.
  WorkApplyRelation _relationFor(WorkDetailModel work, SlotModel? slot) {
    final toId = _to?.id;
    if (toId == null) return WorkApplyRelation.none;
    return ApplicationRelationResolver.resolve(
      myApplications: _myApplications,
      toId: toId,
      slotId: slot?.id,
      work: work,
    );
  }

  // ── [R7-APPLICATION-LIFECYCLE.1C] 확정 일정 겹침 — 같은 공용 owner ──────
  //
  //   `_relationFor` 는 "이 근무에 이미 내 지원이 있는가" 를 본다. 그것과
  //   **다른 사실**이 하나 더 있다: 이 근무 시간에 내가 이미 **다른** 약속을
  //   갖고 있으면 서버가 지원을 거부한다. 이 화면은 그 사실을 보지 않아서
  //   겹치는 업무에도 `선택` 을 그리고 CTA 의 N 에 셌다.
  //
  //   두 사실을 한 enum 으로 합치지 않는다 — 이유가 다르면 문구도 다르다.
  //   판정은 `CommitmentConflictResolver` 한 곳이고 입력은 이미 읽은
  //   `_myApplications` 다(새 쿼리 0).
  //
  //   flex 만 이 자리에서 막는다. 장기·계약형은 **희망 시작일을 아직 고르지
  //   않았다** — 시작일마다 겹침이 달라지므로 여기서 막으면 더 늦은 시작일로
  //   지원할 수 있는 사람을 막는다. 그 판정은 날짜를 고르는 자리
  //   (`LongtermApplySheet._isSelectable`)가 이미 한다.
  CommitmentConflictDecision _commitmentConflictFor(
      WorkDetailModel work, SlotModel? slot) {
    if (!(_to?.isFlexType ?? false)) return CommitmentConflictDecision.none;
    final date = slot?.date;
    if (date == null) return CommitmentConflictDecision.none;
    return CommitmentConflictResolver.forShortTerm(
      commitments: CommitmentConflictResolver.commitmentsOf(_myApplications),
      commitmentsKnown: !_myApplicationsFailed,
      workDate: date,
      startTime: work.startTime,
      endTime: work.endTime,
    );
  }

  /// 선택된 것 중 **신규 지원 가능한** 것만. 카운트와 제출이 같은 목록을 본다.
  ///
  ///   선택 시점에 막아도 그 뒤 데이터가 갱신되면 선택 집합이 낡을 수 있다.
  ///   그래서 세는 자리에서도 다시 걸러낸다.
  List<({SlotModel? slot, WorkDetailModel work})> get _newApplyTargets {
    final out = <({SlotModel? slot, WorkDetailModel work})>[];
    if (_to?.isFlexType ?? false) {
      for (final slot in _allSlots) {
        final wid = _flexSelected[_dateKey(slot.date)];
        if (wid == null) continue;
        final work = slot.workDetails.where((w) => w.id == wid).firstOrNull;
        if (work == null) continue;
        if (_relationFor(work, slot).blocksNewApplication) continue;
        // 확정 일정과 겹치는 근무는 제출 대상이 아니다 — 서버가 거부한다.
        if (_commitmentConflictFor(work, slot).blocksNewApplication) continue;
        out.add((slot: slot, work: work));
      }
    } else {
      for (final work
          in _workDetails.where((w) => _contractSelected.contains(w.id))) {
        if (_relationFor(work, null).blocksNewApplication) continue;
        out.add((slot: null, work: work));
      }
    }
    return out;
  }

  int get _totalSelectedCount => _newApplyTargets.length;

  /// [ISG2-CTA] 이 공고에 **지금 새로 지원할 수 있는** 업무가 하나라도 있는가.
  ///
  ///   하단 CTA 는 선택 개수만 보고 `지원할 업무를 선택해주세요` 라고 했다.
  ///   그런데 유일한 업무가 이미 `지원완료` 면 고를 것이 없다 — 화면이
  ///   할 수 없는 일을 시킨다(실측: QA 공고 10/16, 업무 1개 `지원완료`
  ///   상태에서 CTA 가 그대로였다).
  ///
  ///   판정은 새로 만들지 않는다. `_toggleWork` 가 선택을 거부하는 바로 그
  ///   두 조건(기존 관계·확정 일정 겹침)을 쓴다 — 고를 수 없는 것과
  ///   "고르라"는 문구가 같은 근거를 보게 한다.
  bool get _hasSelectableWork {
    if (_to?.isFlexType ?? false) {
      for (final slot in _allSlots) {
        for (final work in slot.workDetails) {
          if (_relationFor(work, slot).blocksNewApplication) continue;
          if (_commitmentConflictFor(work, slot).blocksNewApplication) continue;
          return true;
        }
      }
      return false;
    }
    for (final work in _workDetails) {
      if (_relationFor(work, null).blocksNewApplication) continue;
      return true;
    }
    return false;
  }

  bool _isWorkSelected(WorkDetailModel work) {
    if (_to?.isFlexType ?? false) {
      if (_selectedSlotDate == null) return false;
      return _flexSelected[_dateKey(_selectedSlotDate!)] == work.id;
    }
    return _contractSelected.contains(work.id);
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _toggleWork(WorkDetailModel work, SlotModel? slot) {
    // [R7-P4.4E.7A] 이미 관계가 있는 근무는 선택 집합에 들어갈 수 없다.
    //   렌더에서 affordance 를 지우는 것만으로는 부족하다 — 낡은 화면에서
    //   눌리는 경로가 남으면 같은 거짓이 되돌아온다.
    if (_relationFor(work, slot).blocksNewApplication) return;
    // [R7-APPLICATION-LIFECYCLE.1C] 확정 일정과 겹치는 근무도 들어갈 수 없다.
    if (_commitmentConflictFor(work, slot).blocksNewApplication) return;
    if (_to?.isFlexType ?? false) {
      if (_selectedSlotDate == null) return;
      final key = _dateKey(_selectedSlotDate!);
      setState(() {
        if (_flexSelected[key] == work.id) {
          _flexSelected.remove(key);
        } else {
          _flexSelected[key] = work.id;
        }
      });
    } else {
      setState(() {
        if (_contractSelected.contains(work.id)) {
          _contractSelected.remove(work.id);
        } else {
          _contractSelected.add(work.id);
        }
      });
    }
  }

  // ── 지원 자격 ──────────────────────────────────

  void _checkApplyEligibility() {
    if (!mounted) return;
    if (widget.mode != TODetailMode.applicant) return;
    final user = context.read<UserProvider>().currentUser;
    String? newReason;
    if (user == null) {
      newReason = '로그인이 필요합니다';
    } else if (user.isBlacklisted) {
      newReason = '이용 제한된 계정입니다';
    } else if (user.isRestricted) {
      final remainDays = user.restrictedUntil!.difference(DateTime.now()).inDays + 1;
      newReason = '무단 결근 페널티 ($remainDays일 제한)';
    } else if (!user.isForeign && !user.isPassVerified) {
      // [PII-DOC-R1.5.3] 내국인만 PASS 필수 — 서버(srvIsForeignIdentity)와
      //   meetsApplyPrerequisites가 쓰는 조건과 같다. 예전에는 국적 구분 없이
      //   막아서, 외국인은 서버가 허용하는 공고에서 버튼이 꺼져 있었다.
      newReason = '본인인증이 필요합니다';
    } else if (!user.hasIdDocument) {
      newReason = '신분증 등록이 필요합니다';
    } else if (_to?.jobType == TOType.flex && !user.isIdVerified) {
      newReason = '신분증 인증이 필요합니다';
    } else if (!user.hasBankAccount) {
      // [PII-DOC-R1.5.4] 지원자 기본자료 차단 사유 복구.
      //   서버 srvMissingApplicantPayoutRegistration과 같은 순서·같은 문구.
      //   예전에는 accountHolder를 빼고 봐서 예금주명만 비었을 때 버튼이
      //   정상으로 보였다 — 이제 hasBankAccount(3필드)로 통일한다.
      newReason = '통장 정보 등록이 필요합니다';
    } else if (!user.hasBankbookDocument) {
      newReason = '통장사본 등록이 필요합니다';
    }
    if (newReason != _applyBlockReason) {
      setState(() => _applyBlockReason = newReason);
    }
  }

  /// 서류 미완료로 인한 차단 여부 — 신분증·통장 관련 사유만 해당
  /// 블랙리스트·페널티·본인인증 차단과 구분하여 바텀시트로 안내
  // [PII-DOC-R1.5.4] '통장' 매칭 복구 — 다시 차단 사유이고, 이 사유들은
  //   사용자가 등록으로 해결할 수 있으므로 버튼을 끄지 않고 시트로 안내한다.
  bool get _isDocumentBlocked {
    final r = _applyBlockReason;
    if (r == null) return false;
    return r.contains('신분증') || r.contains('통장');
  }

  /// [INVITE-CAPACITY] 공고·날짜가 **끝난** 것이 아니라 자리만 찬 상태인가.
  ///   수동 마감·CLOSED/EXPIRED·게시 만료 등이면 false(그건 모집 종료다).
  bool get _closedByCapacityOnly {
    final to = _to;
    if (to == null) return false;
    if (to.isManualClosed ||
        to.status == TOStatus.closed ||
        to.status == TOStatus.expired ||
        (to.isContractType && (to.isPostingExpired || to.isDeadlinePassed))) {
      return false;
    }
    if (_slot?.isEffectivelyClosed == true && _slot?.isFull != true) return false;
    final req = _slot?.workDetails.fold<int>(0, (s, wd) => s + wd.requiredCount)
        ?? widget.slotTotalRequired
        ?? (to.isFlexType ? 0 : to.totalRequired);
    final conf = _slot?.confirmedCount ?? widget.slotConfirmedCount
        ?? (to.isFlexType ? 0 : to.totalConfirmed);
    return to.isFull || (req > 0 && conf >= req);
  }

  bool get _isEffectivelyClosed {
    if (_to == null) return false;
    if (_to!.isClosed) return true;
    // [INVITE-CAPACITY] 슬롯 공고는 공고 합계로 폴백하지 않는다 — 열린 날 필요와
    //   전체 날짜 확정을 비교하게 된다. 슬롯을 모르면 정원으로 마감이라 말하지 않는다
    //   (지원 관문은 서버가 슬롯 단위로 본다).
    final req = _slot?.workDetails.fold<int>(0, (s, wd) => s + wd.requiredCount)
        ?? widget.slotTotalRequired
        ?? (_to!.isFlexType ? 0 : _to!.totalRequired);
    final conf = _slot?.confirmedCount ?? widget.slotConfirmedCount
        ?? (_to!.isFlexType ? 0 : _to!.totalConfirmed);
    if (req > 0 && conf >= req) return true;
    if (widget.slotDate != null) {
      final today = DateTime.now();
      final d = widget.slotDate!;
      if (FormatHelper.toKstDate(d)
          .isBefore(FormatHelper.toKstDate(today))) { return true; }
    }
    if (_to!.isContractType && (_to!.isDeadlinePassed || _to!.isPostingExpired)) return true;
    return false;
  }

  bool _isAnySoonDeadline() {
    if (_to == null) return false;
    if (!_to!.isFlexType) return _to!.isDeadlineSoon;
    final now = DateTime.now();
    if (_slot != null) {
      final dl = _slot!.applicationDeadline;
      if (dl == null) return false;
      final diff = dl.difference(now).inMinutes;
      return diff >= 0 && diff <= 30;
    }
    return _allSlots.any((s) {
      final dl = s.applicationDeadline;
      if (dl == null) return false;
      final diff = dl.difference(now).inMinutes;
      return diff >= 0 && diff <= 30;
    });
  }

  // ── Lifecycle ─────────────────────────────────

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _memCacheWidth = (MediaQuery.sizeOf(context).width *
            MediaQuery.devicePixelRatioOf(context))
        .toInt()
        .clamp(600, 1200);
  }

  @override
  void initState() {
    super.initState();
    _selectedSlotDate = widget.slotDate;
    _loadData();
    // [R5.3D] 공고 로딩과 독립적으로 원 지원을 읽는다 — 공고가 없어도
    //   제안 비교 맥락은 보여줄 수 있어야 한다.
    _loadOfferSource();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _userProvider = context.read<UserProvider>();
        _userProvider!.addListener(_checkApplyEligibility);
        _checkApplyEligibility();
      }
    });
  }

  @override
  void dispose() {
    _galleryController.dispose();
    _userProvider?.removeListener(_checkApplyEligibility);
    super.dispose();
  }

  // ── Data ─────────────────────────────────────

  /// [R7-PAYROLL-POLICY.4C §15] 기준이 바뀌어 지원이 막힌 뒤 **최신 기준을
  /// 다시 보여준다.**
  ///
  ///   별도 policy reader 를 만들지 않는다 — 이 화면의 기존 `_loadData` 가
  ///   사업장을 다시 읽고 `[상세 기준]` 이 그 값을 쓴다. 서버 응답에 정책을
  ///   실어 보내 두 번째 truth source 를 만들지도 않는다.
  ///
  ///   다시 읽기가 실패하면 `_loadData` 의 기존 오류 처리가 ERROR 로 말한다 —
  ///   "기준 없음" 으로 바꾸지 않는다(ERROR ≠ EMPTY). 그 상태에서 자동으로
  ///   다시 지원하지 않는다.
  Future<void> _refreshAfterPolicyChange() async {
    await _loadData();
    if (!mounted) return;
    ToastHelper.showWarning(kAttendancePolicyChangedNote);
  }

  // [R8-PERCEIVED.1] 지원 버튼을 누르면 맨 먼저 세무 축 조회를 기다린다. 그 함수는
  //   지원할 때만 불려 거의 언제나 콜드라(DEV 14일: 11건 중 콜드 분 9건, 시작 p50
  //   1.17초) 탭 뒤 화면이 수 초간 아무 반응이 없었다. 상세를 여는 동안(스피너가 이미
  //   떠 있다) 같은 조회를 먼저 출발시키고 탭에서 **한 번만** 쓴다.
  //   판정은 그대로다 — 60초가 지났거나 실패했으면 탭에서 다시 읽고(기존과 같음),
  //   최종 판단은 여전히 callableApplyToTO 다. 첫 렌더는 이 조회를 기다리지 않는다.
  static const Duration _taxPrefetchMaxAge = Duration(seconds: 60);
  Future<TaxIdentityStatus>? _taxPrefetch;
  DateTime? _taxPrefetchAt;

  void _startTaxPrefetch() {
    _taxPrefetchAt = _reads.now();
    _taxPrefetch = _reads
        .taxStatus()
        .catchError((Object _) => const TaxIdentityStatus.unknown());
  }

  Future<TaxIdentityStatus> _takeTaxStatus() async {
    final pending = _taxPrefetch;
    final at = _taxPrefetchAt;
    _taxPrefetch = null;
    _taxPrefetchAt = null;
    if (pending != null &&
        at != null &&
        _reads.now().difference(at) < _taxPrefetchMaxAge) {
      final status = await pending;
      if (!status.loadFailed) return status;
    }
    return _reads.taxStatus();
  }

  Future<void> _loadData() async {
    _applicantUid = widget.mode == TODetailMode.applicant
        ? context.read<UserProvider>().currentUser?.uid
        : null;
    if (_applicantUid != null) _startTaxPrefetch();
    setState(() => _isLoading = true);
    try {
      if (widget.to != null) {
        _to = widget.to;
        _workDetails = widget.workDetails ?? [];
        _business = widget.business;
      } else if ((widget.toId ?? '').isEmpty) {
        // [R5.3D] 공고를 특정할 식별자가 없다 — 초대 조건만 보여준다.
        //   '없는 초대'로 만들지 않는다.
        _to = null;
        _loadFailed = true;
      } else {
        // [SYSTEM-INTEGRATION-POSTING-1] 못 읽은 것과 없는 것을 구분해서 받는다.
        final loaded = await _reads.toOrFailure(widget.toId!);
        _to = loaded.to;
        _loadFailed = loaded.failed;
        if (_to != null) {
          final results = await Future.wait([
            _reads.workDetails(_to!.id),
            _reads.businessById(_to!.businessId),
          ]);
          _workDetails = results[0] as List<WorkDetailModel>;
          _business = results[1] as BusinessModel?;
        }
      }
      if (_business == null && _to != null) {
        await Future.wait([
          _reads.businessById(_to!.businessId)
              .then((biz) { _business = biz; }),
          if (_to!.isFlexType) _loadSlots(),
          if (widget.mode == TODetailMode.applicant && _applicantUid != null)
            _reads.myApplications(_applicantUid!)
                .then((apps) { _myApplications = apps; })
                .catchError(_onMyApplicationsFailed),
        ]);
        if (_business != null) await _loadWorkTypes();
      } else {
        await Future.wait([
          if (_to != null && _to!.isFlexType) _loadSlots(),
          if (_business != null) _loadWorkTypes(),
          if (widget.mode == TODetailMode.applicant && _applicantUid != null)
            _reads.myApplications(_applicantUid!)
                .then((apps) { _myApplications = apps; })
                .catchError(_onMyApplicationsFailed),
        ]);
      }
    } catch (e) {
      debugPrint('❌ 데이터 로드 실패: $e');
      if (mounted) ToastHelper.showError('데이터를 불러오는데 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSlots() async {
    try {
      _slotLoadError = false;
      final slots = await _reads.slots(_to!.id, visibleOnly: false);
      final now = DateTime.now();
      _allSlots = slots
          .where((s) => !s.isEffectivelyClosed)
          .where((s) => s.visibleFrom == null || !s.visibleFrom!.isAfter(now))
          .toList();

      // 진단 로그: 슬롯 필터 결과 (날짜 미표시 원인 파악용)
      if (slots.isEmpty) {
        debugPrint('📅 [SLOT] TO(${_to!.id}): 슬롯 없음 (Firestore subcollection 비어있음)');
      } else if (_allSlots.isEmpty) {
        final closedCount = slots.where((s) => s.isEffectivelyClosed).length;
        final hiddenCount = slots.where((s) =>
            s.visibleFrom != null && s.visibleFrom!.isAfter(now)).length;
        debugPrint(
          '📅 [SLOT] TO(${_to!.id}): 전체 ${slots.length}개 중 유효 0개 '
          '(isEffectivelyClosed: $closedCount, visibleFrom 미도달: $hiddenCount)',
        );
      } else {
        debugPrint('📅 [SLOT] TO(${_to!.id}): 유효 슬롯 ${_allSlots.length}개');
      }

      if (widget.slotDate != null) {
        // [R7-P2-2 후속 P22-D] 밖에서 들어온 날짜는 **이 목록과 표현이 다르다.**
        //
        //   슬롯의 `date` 는 Firestore 가 내려준 값(`toDate().toLocal()`)이고,
        //   목록이 넘겨 주는 선택 날짜는 KST 정규화 키다. 비-KST 기기에서는
        //   두 값의 `.year/.month/.day` 가 하루 어긋나 **고른 날의 슬롯을
        //   못 찾는다** — 방금 고른 날짜가 상세에서 사라진다.
        //   날짜 owner(P1-3)의 KST 달력일로 맞춘다.
        final sd = FormatHelper.toKstDate(widget.slotDate!);
        _slot = slots
            .where((s) => FormatHelper.toKstDate(s.date) == sd)
            .firstOrNull;
        if (_slot != null) {
          // 찾았으면 **목록의 표현**으로 되돌린다 — 이 화면의 나머지 비교는
          //   전부 슬롯의 `date` 를 기준으로 돌아간다.
          _selectedSlotDate = _slot!.date;
          if (_workDetails.isEmpty) _workDetails = _slot!.workDetails;
        }
      }
      _selectedSlotDate ??= _allSlots.firstOrNull?.date;
    } on FlexSlotOverflowException catch (e) {
      // [POSTING-V2-03C.1] 잘린 목록을 정상처럼 두지 않는다.
      //   toast만으로는 신호가 사라지므로 화면에 남는 실패 상태로 기록한다 —
      //   '근무 날짜 없음'과 같은 화면이 되면 안 된다.
      debugPrint('⚠️ 슬롯 로드 실패(상한 초과): $e');
      _allSlots = [];
      _slotLoadError = true;
      if (mounted) {
        ToastHelper.showError('근무 일정을 불러오지 못했습니다');
      }
    } catch (e) {
      // [POSTING-V2-03D.1] 상한 초과만 실패로 다루지 않는다.
      //   네트워크·권한 등 일반 조회 실패도 근무 날짜를 모르는 상태이므로
      //   '근무 날짜 없음' 화면으로 내려앉으면 안 된다. ERROR != EMPTY.
      debugPrint('⚠️ 슬롯 로드 실패: $e');
      _allSlots = [];
      _slotLoadError = true;
      if (mounted) {
        ToastHelper.showError('근무 일정을 불러오지 못했습니다');
      }
    }
  }

  Future<void> _loadWorkTypes() async {
    try {
      _workTypeCatalog = await _reads.workTypeCatalog(_business!.id);
    } catch (e) {
      debugPrint('⚠️ 업무유형 로드 실패: $e');
    }
  }

  // ── [CROSS-DOMAIN-R5.3D] 통합 초대 projection ──────────────────────────

  /// 원 지원(A) — '다른 업무 제안'일 때만 비교 맥락으로 쓴다.
  /// 읽지 못하면 null이고, 그때는 비교만 생략한다(없다고 말하지 않는다).
  ApplicationModel? _offerSourceApplication;

  /// [R5.3D.1] 이 화면이 초대 상세로 동작하는가.
  ///
  /// 이 값이 true면 공고의 현재 모집 정보는 **결정 흐름에서 빠진다**.
  /// 초대는 이미 정해진 조건에 답하는 일이고, 공고를 탐색하는 일이 아니다.
  bool get _isInvitationDetail {
    final app = widget.myApplication;
    return app != null && app.status == AppStatus.invited;
  }

  /// [R5.3D.1] 현재 모집 정보 — **보조 공개**.
  ///
  /// 지우지 않는다. 근로자가 이 사업장이 지금 무엇을 모집하는지 궁금할 수
  /// 있고, 그건 정당한 질문이다. 다만 그 숫자가 "내가 수락할 조건"과
  /// 같은 자리에 있으면 안 된다 — 기본은 접혀 있고 이름이 다르다.
  Widget _buildCurrentRecruitingDisclosure(BuildContext context) {
    final s = ResponsiveHelper.spacing(context, 16);
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      color: Colors.white,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.symmetric(horizontal: s),
          childrenPadding: EdgeInsets.zero,
          leading: Icon(Icons.storefront_outlined,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.grey500),
          title: Text(
            '이 사업장의 현재 모집 정보',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '초대 조건과는 별개입니다.',
            style:
                ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
          ),
          children: [
            if (_to!.isFlexType && _slotLoadError)
              _buildSlotLoadErrorMessage(context)
            else if (_to!.isFlexType && _allSlots.isNotEmpty)
              _buildDatePicker(context)
            else if (_to!.isFlexType && _allSlots.isEmpty)
              _buildNoSlotsMessage(context),
            _buildWorkSection(context),
          ],
        ),
      ),
    );
  }

  /// 이 화면이 **초대 상세**로 동작해야 하는가, 그렇다면 무엇을 보여주는가.
  ///
  /// INVITED가 아니면 null — 일반 공고 상세는 지금 동작 그대로다.
  /// 두 개의 동등한 상세 화면을 만들지 않기 위해 같은 화면에 층을 얹는다.
  InvitationProjection? _invitationProjection({required bool postingLoaded}) {
    final app = widget.myApplication;
    if (app == null || app.status != AppStatus.invited) return null;
    return InvitationProjection.of(
      application: app,
      postingLoaded: postingLoaded,
      // 공고를 읽었을 때만 차이를 계산한다 — 못 읽은 것을 '달라졌다'고 하지 않는다.
      liveWorkDetail: postingLoaded ? _liveWorkDetailForApplication(app) : null,
    );
  }

  /// 약속과 비교할 **현재** workDetail. wdId가 canonical이고, 없으면 비교하지 않는다.
  WorkDetailModel? _liveWorkDetailForApplication(ApplicationModel app) {
    for (final w in _workDetails) {
      if (app.wdId != null && app.wdId!.isNotEmpty && w.wdId == app.wdId) {
        return w;
      }
    }
    return null;
  }

  /// 제안이면 원 지원을 한 건만 읽어 둔다 — 비교 맥락용.
  Future<void> _loadOfferSource() async {
    final app = widget.myApplication;
    final srcId = app?.sourceApplicationId;
    if (app == null || !app.isAlternativeWorkOffer || srcId == null) return;
    try {
      final one = await _reads.applicationOnce(srcId);
      if (!mounted) return;
      // 본인 소유일 때만 쓴다 — 남의 지원서가 화면에 오지 않게.
      if (one != null && one.uid == app.uid) {
        setState(() => _offerSourceApplication = one);
      }
    } catch (e) {
      debugPrint('⚠️ [R5.3D] 원 지원서 조회 실패: $e');
    }
  }

  // ── Build ─────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // [DU1 구현70 VQ-02] 흰 섹션 사이로 회색 바탕(8px 띠)이 비쳐 머리말·날짜·업무·내 지원 일정·근태·길안내가
      //   띠로 토막났고 '내 지원 일정'은 회색 덩어리로 보였다(시안: 한 흰 면 + 제목·간격으로 구분, 구현69 홈과 같은 결정).
      //   바탕을 흰 면으로 맞춘다. 섹션 순서·내용·여백 값은 그대로.
      backgroundColor: AppColors.surface,
      body: _isLoading
          ? const LoadingWidget(message: '공고 정보를 불러오는 중...')
          : _to == null
              // [CROSS-DOMAIN-R5.3D] 공고를 못 읽었다고 초대가 없어지지 않는다.
              //   약속은 Application에 남아 있고, 근로자는 그 조건을 보고
              //   답할 수 있어야 한다. context만 없는 것이다 — UNKNOWN ≠ EMPTY.
              ? (_invitationProjection(postingLoaded: false) != null
                  ? InvitationFallbackDetail(
                      projection: _invitationProjection(postingLoaded: false)!,
                      sourceApplication: _offerSourceApplication,
                      actions: _buildBottomBar(context),
                      onRetryPosting: _loadData,
                    )
                  : _buildErrorState(context))
              : CustomScrollView(
                  slivers: [
                    _buildGalleryAppBar(context),
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPostingHeader(context),
                          // [CROSS-DOMAIN-R5.3D] 초대라면 **수락하면 적용될
                          //   조건**이 결정의 유일한 근거다.
                          if (_invitationProjection(postingLoaded: true) != null)
                            InvitationPromiseCard(
                              projection:
                                  _invitationProjection(postingLoaded: true)!,
                              sourceApplication: _offerSourceApplication,
                            ),
                          // 내 지원에서 진입 시: Application 상태 카드
                          if (widget.myApplication != null)
                            _buildMyApplicationSection(context),
                          // [CROSS-DOMAIN-R5.3D.1] 초대 상세에서는 공고의
                          //   **현재 모집 정보**를 promise와 나란히 놓지 않는다.
                          //
                          //   promise 카드에서 120,000원을 본 사람이 바로 아래
                          //   같은 업무의 공고 현재 금액을 동등한 카드로 다시
                          //   보면, 어느 쪽이 적용되는지 알 수 없다. 초대 대상이
                          //   아닌 다른 모집 업무도 이 결정과 관계가 없다.
                          //   날짜 선택기도 마찬가지다 — 초대는 특정 날짜 건이다.
                          //
                          //   지우지는 않는다. 접힌 보조 영역으로 내리고
                          //   "현재 모집 정보"라고 이름 붙여 decision truth가
                          //   아님을 분명히 한다.
                          if (!_isInvitationDetail) ...[
                            // [POSTING-V2-03C.1] 불러오기 실패가 '날짜 없음'과
                            //   같은 화면이 되지 않도록 먼저 가른다.
                            if (_to!.isFlexType && _slotLoadError)
                              _buildSlotLoadErrorMessage(context)
                            else if (_to!.isFlexType && _allSlots.isNotEmpty)
                              _buildDatePicker(context)
                            else if (_to!.isFlexType && _allSlots.isEmpty)
                              _buildNoSlotsMessage(context),
                            _buildWorkSection(context),
                          ] else
                            _buildCurrentRecruitingDisclosure(context),
                          // 내 지원 일정 — 단기/장기 공통, 업무 목록 바로 아래
                          // [CP05] 화면 좌우 gutter 로 맞춘다(위젯 내용·조건 그대로).
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                                _gutter(context), ConceptSpace.infoGroupGap, _gutter(context), 0),
                            child: ApplySummarySection(
                              myApplications: _myApplications,
                              currentToId: _to?.id,
                            ),
                          ),
                          // [R7-PAYROLL-POLICY.4 §33] 근태 기준은 급여 금액을
                          //   바꾼다 — 지원 전에 확인할 수 있어야 한다.
                          //   [.29-A1] 핵심 기준을 처음부터 보인다(사례만 접힘). 내 지원에서 오면 그 지원서 snapshot.
                          if (_business != null)
                            _buildAttendancePolicyDisclosure(context),
                          if (_business?.precautions != null &&
                              _business!.precautions!.isNotEmpty)
                            _buildPrecautionsSection(context),
                          if (_business != null) _buildFacilitiesSection(context),
                          if (_business != null) _buildTransportSection(context),
                          // [BOTTOM-BAR-DOUBLE-COUNT] 하단 CTA 는
                          //   `bottomNavigationBar` 라 Scaffold 가 이미 그
                          //   높이를 본문에서 빼 준다. 여기서 100dp 를 또
                          //   비우면 바를 두 번 피하는 셈이라, 끝까지 내렸을
                          //   때 마지막 카드와 CTA 사이에 90px(360dp 실측)가
                          //   남았다. 섹션 사이 간격(8dp) 리듬에 맞춘다.
                          // [CP05] 정밀 §8 정보→CTA 16(배율 곱 없음).
                          const SizedBox(height: ConceptSpace.infoToCta),
                        ],
                      ),
                    ),
                  ],
                ),
      // 공고를 못 읽은 초대는 위 fallback이 자체 CTA를 갖는다.
      bottomNavigationBar:
          _isLoading || _to == null ? null : _buildBottomBar(context),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    // [SYSTEM-INTEGRATION-POSTING-1] 못 읽은 것을 없어진 것으로 말하지 않는다.
    //   딥링크로 들어온 사람에게 둘은 완전히 다른 얘기다 — 하나는 기다렸다
    //   다시 열면 되고, 하나는 끝난 공고다.
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_loadFailed ? Icons.wifi_off : Icons.error_outline,
              size: 64, color: AppColors.grey400),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(_loadFailed ? '공고를 불러오지 못했습니다' : '공고를 찾을 수 없습니다',
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(color: AppColors.grey600)),
          if (_loadFailed) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text('네트워크 상태를 확인한 뒤 다시 시도해주세요',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey500)),
          ],
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          if (_loadFailed)
            CommonWidgets.outlineButton(
              context: context,
              text: '다시 시도',
              onPressed: _loadData,
              icon: Icons.refresh,
            )
          else
            CommonWidgets.outlineButton(
              context: context,
              text: '돌아가기',
              onPressed: () => Navigator.pop(context),
              icon: Icons.arrow_back,
            ),
        ],
      ),
    );
  }

  // ── 1. 갤러리 앱바 ────────────────────────────

  Widget _buildGalleryAppBar(BuildContext context) {
    final images = _galleryImages;
    final hasImages = images.isNotEmpty;
    final hasMultiple = images.length > 1;

    // 이미지 없음: 흰색 일반 앱바만 표시 (대형 placeholder 금지)
    if (!hasImages) {
      return SliverAppBar(
        pinned: true,
        floating: false,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.white,
        // [CP05] 시안·Q6 화면 타이틀 — 대상 중심 명사형 `일자리 상세`(사진 없는 흰 앱바에만. 사진 갤러리 분기는 그대로).
        centerTitle: true,
        title: Text('일자리 상세',
            style: ConceptText.body().copyWith(fontWeight: FontWeight.w700)),
        // [DU1 구현112 S041 뒤로 hit] 원(40)·아이콘 모양은 그대로 두고 누르는 영역만 leading 슬롯 전체(56×56)로 넓힌다.
        //   이전에는 GestureDetector 가 Padding(8) 안 원 Container 에 붙어 원 안쪽(반지름 20)만 닿았다
        //   — 40 상자 모서리·중심 기준 48 상자 8점 미도달(구현112 실측). opaque 라 Padding 여백도 같은 receiver 가 받는다.
        //   사진 있는 갤러리 분기 뒤로도 같은 구조이나 이번 범위가 아니다(별도 후보).
        // [DU1 구현116 S041 뒤로 의미 label] 사진 없는 분기 custom 뒤로는 tap 동작만 있고 이름·역할이 없었다(구현116 semantics 실측: label ""·isButton false).
        //   기존 MaterialLocalizations 의 뒤로 이름(ko '뒤로')과 button 역할을 같은 노드에 단다. 크기·hit·Navigator.pop 은 그대로다.
        leading: Semantics(
          container: true,
          button: true,
          label: MaterialLocalizations.of(context).backButtonTooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.grey100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back,
                    color: AppColors.textPrimary, size: 20),
              ),
            ),
          ),
        ),
        actions: [
          if (widget.mode == TODetailMode.adminPreview)
            Container(
              margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.visibility, size: 15, color: Colors.white),
                  const SizedBox(width: 4),
                  Text('미리보기',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
        ],
      );
    }

    // 이미지 있음: 사업장 갤러리 앱바
    final double expandedHeight = hasMultiple ? 300 : 240;

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      // [DU1 구현115 S041 접힌 사진 머리 비침] black87(불투명도 87%)이라 완전히 접힌 뒤 머리 아래로 스크롤된 본문 사업장명이 비쳐
      //   뒤로 원·화살표와 겹쳤다(구현113·114 관측, 구현115 A/B: 같은 RGB 의 불투명 black 에서 사라짐). 흰 본문 위 black87 의
      //   겉보기(#222222)와 같은 계열의 불투명 토큰으로 바꾼다. 펼친 상태는 사진이 이 바탕을 덮는다.
      backgroundColor: AppColors.grey900,
      foregroundColor: Colors.white,
      elevation: 0,
      // [DU1 구현113 S041 사진 있는 분기 뒤로 hit] 원(40)·아이콘 모양은 그대로 두고 누르는 영역만 leading 슬롯 전체(56×56)로 넓힌다.
      //   이전에는 원 안쪽(반지름 20)만 뒤로가 받고, 슬롯의 나머지 탭은 아래 배경 사진(PageView 항목 GestureDetector)으로 떨어져
      //   사진 미리보기가 열렸다 — 접힌 상태에서도 보이지 않는 배경이 받았다(구현113 실측). opaque 라 슬롯 안 탭은 뒤로가 받는다.
      //   사진 없는 분기(구현112)와 같은 방식이다. 툴바의 나머지 영역 탭이 배경 미리보기로 가는 것은 이번 범위가 아니다.
      // [DU1 구현116 S041 뒤로 의미 label] 사진 있는 분기 custom 뒤로는 tap 동작만 있고 이름·역할이 없었다(구현116 semantics 실측: label ""·isButton false).
      //   기존 MaterialLocalizations 의 뒤로 이름(ko '뒤로')과 button 역할을 같은 노드에 단다. 크기·hit·Navigator.pop 은 그대로다.
      leading: Semantics(
        container: true,
        button: true,
        label: MaterialLocalizations.of(context).backButtonTooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.pop(context),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            ),
          ),
        ),
      ),
      actions: [
        if (widget.mode == TODetailMode.adminPreview)
          Container(
            margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.visibility, size: 15, color: Colors.white),
                const SizedBox(width: 4),
                Text('미리보기',
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: Stack(
          fit: StackFit.expand,
          children: [
            // 메인 이미지 (PageView) — 탭으로 전체화면 미리보기 가능
            // [DU1 구현114 S041 접힌 사진 숨은 탭] 완전히 접혀 배경이 보이지 않을 때만 사진이 탭·넘김을 받지 않는다(_GalleryHiddenInputGate).
            //   펼침·중간 접힘(배경이 보이는 동안)과 사진 미리보기 동작은 그대로다.
            _GalleryHiddenInputGate(
              child: PageView.builder(
                controller: _galleryController,
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _galleryPage = i),
                // [DU1 구현118 S041 사진 미리보기 의미 이름] 사진 tap receiver 는 동작만 있고 이름·역할이 없었다(구현118 semantics 실측: label ""·isButton false).
                //   같은 노드에 '사업장 사진 미리보기' 이름과 button 역할을 단다. 동작(showImagePreview)·크기·hit 는 그대로다.
                itemBuilder: (_, i) => Semantics(
                  container: true,
                  button: true,
                  label: '사업장 사진 미리보기',
                  child: GestureDetector(
                    onTap: () => CommonWidgets.showImagePreview(
                      context, images,
                      initialIndex: i,
                    ),
                    child: ImageHelper.buildCachedImage(
                      images[i],
                      fit: BoxFit.cover,
                      memCacheWidth: _memCacheWidth,
                      fadeInDuration: const Duration(milliseconds: 150),
                    ),
                  ),
                ),
              ),
            ),
            // 그라데이션 오버레이 (상단/하단)
            // IgnorePointer 필수: decoration이 있는 Container는 기본적으로
            // HitTestBehavior.opaque → 아래 PageView 제스처(스와이프)를 차단함
            IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.25, 0.75, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.3),
                    ],
                  ),
                ),
              ),
            ),
            // 우하단 페이지 인디케이터 "1/4"
            if (hasMultiple)
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_galleryPage + 1}/${images.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 2. 공고 헤더 ──────────────────────────────

  /// [CP05] 정밀 §8 — 화면 좌우 여백(gutter). 320 계열 16·그 외 20, 글자 배율을 다시 곱하지 않는다.
  double _gutter(BuildContext context) => ConceptSpace.gutter(MediaQuery.sizeOf(context).width);

  /// [CP05] 정밀 §8 — 표면 밖 섹션 제목 20/700(장식 아이콘 없음). 낱말 단위 줄바꿈, 의미 이름은 원문.
  Widget _sectionTitle(String text) =>
      Text(TextLayout.keepWords(text), semanticsLabel: text, style: ConceptText.section());

  Widget _buildPostingHeader(BuildContext context) {
    final g = _gutter(context);

    final isEffectivelyClosed = _isEffectivelyClosed;
    final isSoonDeadline = !isEffectivelyClosed && _isAnySoonDeadline();

    // [R7-P1-2] 모집중은 진행 상태다 — green 은 달성(충족·확정)에 남긴다.
    //   solid pill 이므로 CTA brand(#1565C0)와 구분되는 infoMedium(#1E88E5)을 쓴다.
    // [INVITE-CAPACITY] FULL ≠ DONE — 자리가 다 찬 것과 모집이 끝난 것을 다르게 말한다.
    final (statusLabel, statusColor) = isEffectivelyClosed
        ? (_closedByCapacityOnly ? ('인원 마감', AppColors.grey500) : ('모집 종료', AppColors.grey500))
        : isSoonDeadline
            ? ('마감임박', AppColors.warning)
            : ('모집중', AppColors.infoMedium);

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(g, 16, g, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [CP05] 정밀 §4·§9 — 실제 분류(업종·세부 업종)·근무 유형·대표 지급 방식 필을 사업장명 위에 모은다(시안 순서).
          _buildWorkTypeBadgeChips(context),
          // ── 사업장 영역 ────────────────────────────
          if (_business != null) ...[
            // 사업장명 (공고 제목보다 크게, 명확하게)
            // [DU1] 큰 글씨에서 '사업|장'처럼 음절로 끊지 않는다 — 단어 단위 줄바꿈
            // [CP05] 정밀 §8 — 상세 사업장 28/700/1.25/−0.2, 길면 여러 줄. 의미 이름은 원문.
            Text(
              TextLayout.keepWords(_business!.name),
              semanticsLabel: _business!.name,
              style: ConceptText.detailBusiness(),
            ),
            // 핵심 시설/환경 배지 칩
            const SizedBox(height: 8),
            _buildFacilityBadgeChips(context),
            // 한줄 소개
            // [CP05] 정밀 §8 — 사업장이 쓴 소개는 말줄임 없이 메타 14 로 전문을 보인다.
            if (_business!.oneLineIntro != null &&
                _business!.oneLineIntro!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _business!.oneLineIntro!,
                style: ConceptText.meta(),
              ),
            ],
            // [DU-VQ-02] 사업장과 공고는 한 머리말이다 — 구분선(+위아래 16)이 두 덩어리로 끊어 읽게 했다. 간격만 둔다.
            const SizedBox(height: ConceptSpace.infoGroupGap),
          ],

          // ── 공고 영역 ──────────────────────────────
          // 공고 제목 + 상태 배지 (사업장명보다 작은 위계)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // [DU-VQ-02] 사업장명(bold 큰 글씨) 바로 아래라 같은 bold 로 경쟁했다 — 한 단계 가볍게(w600, 기존 결정: 사업장명이 위)
                // [CP05] 정밀 §8 — 본문 16(사업장 28 아래 한 단계), 굵기 700.
                child: Text(
                  _to!.title,
                  style: ConceptText.body().copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              // [DU1] 채운 알약(흰 글자) → 옅은 배경 + 진한 글자 배지(시안). 흰 글자/warning(#FF9800) 대비 2.2:1 해소.
              //   의미 구분은 그대로: 모집중=brand · 마감임박=warning · 종료/인원 마감=중립(FULL ≠ DONE 문구 유지).
              Builder(builder: (context) {
                final (bg, fg) = statusColor == AppColors.warning
                    ? (AppColors.warningBg, AppColors.warningDark)
                    : statusColor == AppColors.grey500
                        ? (AppColors.grey100, AppColors.textSecondary)
                        : (AppColors.brandSurface, AppColors.brand);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    // [CP05] 정밀 §8 상태 필 13/700(글자색은 위 쌍의 fg 그대로).
                    style: ConceptText.pill(fg).copyWith(color: fg),
                  ),
                );
              }),
            ],
          ),
          // 공고 설명
          // [CP05] 정밀 §8 — 공고 본문은 업무·본문 16 으로, 말줄임 없이 전문(중요 조건을 3줄로 자르지 않는다).
          if (_to!.description != null && _to!.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _to!.description!,
              style: ConceptText.body(color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  /// 사업장 시설 배지 칩 (냉장물류, 주차가능, 중식제공 등)
  Widget _buildFacilityBadgeChips(BuildContext context) {
    final chips = <String>[];

    // 시설 목록
    if (_business!.facilities?.isNotEmpty == true) {
      chips.addAll(_business!.facilities!.take(2));
    }
    // 주차
    if (_business!.parkingAvailable) chips.add('주차 가능');
    // 식사
    if (_business!.mealsProvided?.isNotEmpty == true) {
      final meal = _business!.mealsProvided!.first;
      chips.add('$meal 제공');
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips.map((chip) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.grey200),
        ),
        child: Text(
          chip,
          style: ResponsiveHelper.tinyStyle(context)
              .copyWith(color: AppColors.grey700, fontWeight: FontWeight.w500),
        ),
      )).toList(),
    );
  }

  /// 근무유형 배지 칩 (단기, 익일지급, 장기가능 등)
  /// [CP05] 정밀 §4 상세 분류 필 — 실제 업종·세부 업종(사업장 문서 값 그대로)을 맨 앞에 두고,
  ///   근무 유형·대표 지급 방식(첫 업무 기준, 기존 제한 그대로)과 같은 분류 필(#E4ECFD/#25325B 13/700 H10/V4 r8)로 통일한다.
  ///   색으로 단기/장기·지급 방식을 구별하던 보라·초록은 쓰지 않는다(글자가 구별한다).
  Widget _buildWorkTypeBadgeChips(BuildContext context) {
    final chips = <String>[];

    // 실제 분류 — 비어 있으면 넣지 않는다(새 값 추정 0). 업종과 세부 업종이 같으면 한 번만.
    final biz = _business;
    if (biz != null) {
      final parts = <String>[
        for (final v in [biz.category.trim(), biz.subCategory.trim()])
          if (v.isNotEmpty) v,
      ];
      if (parts.length == 2 && parts[0] == parts[1]) parts.removeLast();
      if (parts.isNotEmpty) chips.add(parts.join(' · '));
    }

    // 근무 유형
    chips.add(_to!.jobTypeLabel);

    // 대표 급여 지급 방식 (첫 번째 workDetail 기준)
    if (_workDetails.isNotEmpty) {
      final payLabel = _workDetails.first.payScheduleTypeLabel;
      if (payLabel.isNotEmpty) {
        chips.add(payLabel);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: ConceptSpace.promiseChipToBusiness),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: chips.map((c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: ConceptSurface.category(),
          child: Text(
            TextLayout.keepWords(c),
            semanticsLabel: c,
            style: ConceptText.pill(AppColors.conceptNavy),
          ),
        )).toList(),
      ),
    );
  }

  // ── 3. 날짜 선택 (flex TO) ────────────────────

  /// 단기 공고인데 유효한 슬롯이 없을 때 — 날짜 선택기 대신 안내 메시지
  /// (슬롯 미생성 / 마감 초과 / visibleFrom 미도달 공통 처리)
  Widget _buildNoSlotsMessage(BuildContext context) {
    // [CP05] 정밀 §4·§8 — 선택할 날짜가 없는 것은 오류가 아니다(중립 보조 글자). 여백은 gutter·섹션 간격. 문구 그대로.
    final g = _gutter(context);
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(g, ConceptSpace.sectionGap, g, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.event_busy_outlined,
                size: 18,
                color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),
          // [R8-INTEGRATED §8] 제약 없는 Text 가 Row 를 넘겼다 — 360dp 에서 30px.
          //   아래 `_buildSlotLoadErrorMessage` 는 같은 구조에 Expanded 를
          //   쓰고 있었다. 같은 컨테이너의 두 문장이 다른 규칙을 쓰고 있었다.
          Expanded(
            child: Text(
              '현재 선택 가능한 근무 날짜가 없습니다.',
              style: ConceptText.body(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// [POSTING-V2-03C.1] 근무일 목록을 완전하게 불러오지 못했을 때.
  ///
  /// _buildNoSlotsMessage와 같은 컨테이너를 쓰되 **실패**임을 말한다.
  /// 근무일이 실제로 없는 것이 아니라 확인할 수 없는 상태다.
  Widget _buildSlotLoadErrorMessage(BuildContext context) {
    // [CP05] 정밀 §4 상세 — 조회 실패는 errorDark(선택 불가·날짜 없음과 다른 상태). 여백은 gutter·섹션 간격. 문구 그대로.
    final g = _gutter(context);
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(g, ConceptSpace.sectionGap, g, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.cloud_off_rounded,
                size: 18,
                color: AppColors.errorDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '근무 일정을 불러오지 못했습니다.\n잠시 후 다시 시도해주세요.',
              style: ConceptText.body(color: AppColors.errorDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context) {
    final s = _gutter(context);
    // [CP05] 정밀 §8·§9 — 섹션 제목 20/700 + 열람 문맥 한 줄(14). 날짜를 고르는 것은 **그날 업무를 보는 것**이고
    //   지원 선택(업무 `선택`)과 다르다 — 문구가 그 차이를 말한다(열람일 ≠ 지원 선택).
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(top: ConceptSpace.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('근무 날짜'),
                const SizedBox(height: 4),
                Text(
                  TextLayout.keepWords('날짜를 고르면 그날의 업무가 보여요'),
                  semanticsLabel: '날짜를 고르면 그날의 업무가 보여요',
                  style: ConceptText.meta(),
                ),
              ],
            ),
          ),
          const SizedBox(height: ConceptSpace.sectionTitleToCard),
          // [R7-P2-2 후속 P22-D] 날짜 칩 줄은 높이 82·폭 62 로 고정돼 있었다.
          //   요일·날짜·가능한 업무 수 세 줄이 들어가는 칸이라 글자를 키우면
          //   **업무 수가 잘려 어느 날에 무엇이 열려 있는지 잃는다.**
          //   글자 배율을 따라간다(상한은 둬서 목록이 화면을 삼키지 않게).
          // [DU1] 고정 높이(배율 비례)는 번들 NotoSansKR·320dp·2.0 에서 35~47px 넘쳤다 — 칩 줄 높이를 내용에 맞춘다.
          //   가로 스크롤은 그대로, 같은 줄의 칩은 가장 긴 칩 높이로 맞춘다(IntrinsicHeight). 날짜 수는 공고 기간이라 많지 않다.
          // 전폭 유지 — 가로 스크롤 뷰는 내용 폭만 잡아 섹션 흰 바탕이 칩 너비에서 끊겼다(C8 기본 배율 회귀)
          SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: s),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final slot in _allSlots) _buildDateChip(context, slot)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  double _dateChipWidth(BuildContext context) =>
      // [DU1] 320dp·2.0 에서 '업무 1개'가 두 줄로 꺾여 칩이 넘쳤다 — 폭 기준을 늘린다
      MediaQuery.textScalerOf(context).scale(76).clamp(76.0, 170.0);

  Widget _buildDateChip(BuildContext context, SlotModel slot) {
    final theme = Theme.of(context);
    // [R7-P2-2 후속 P22-D] **보이는 날짜**는 KST 달력일이다.
    //   슬롯의 `date` 는 기기 로컬 표현이라 비-KST 기기에서는 그 필드가
    //   하루 어긋난다 — 그대로 쓰면 "10월 11일 근무"가 "10월 10일"로 보인다.
    //   비교는 슬롯 표현끼리(자기 일관), 표시만 KST 로 바꾼다.
    final date = FormatHelper.toKstDate(slot.date);
    final isSelected = _selectedSlotDate != null &&
        FormatHelper.toKstDate(_selectedSlotDate!) == date;

    final weekDays = ['월', '화', '수', '목', '금', '토', '일'];
    final dayLabel = weekDays[date.weekday - 1];

    // 가능한 업무 수
    final availableCount = slot.workDetails
        .where((wd) => !wd.isTimeExpired)
        .length;
    final isClosed = slot.isEffectivelyClosed || availableCount == 0;
    // [CP05] 정밀 §4 — 주말은 다른 날과 같은 보조 글자색(빨강 0), 선택만 brand. 마감 칸은 흐린 중립.
    final weekdayColor = isClosed ? AppColors.grey400 : AppColors.textSecondary;

    // 선택은 **슬롯의 표현**으로 저장한다 — 나머지 비교가 그 기준이다.
    // [CP05] 의미 node 하나(날짜·요일·업무 수 원문, 선택·사용 가능 상태)에 물리 receiver 와 같은 콜백을 단다.
    void view() => setState(() => _selectedSlotDate = slot.date);
    final countLabel = isClosed ? '마감' : '업무 ${slot.workDetails.length}개';
    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      enabled: !isClosed,
      label: '${date.month}월 ${date.day}일 $dayLabel요일, $countLabel',
      excludeSemantics: true,
      onTap: isClosed ? null : view,
      child: GestureDetector(
      onTap: isClosed ? null : view,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: _dateChipWidth(context),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primaryColor
              : isClosed
                  ? AppColors.grey100
                  : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? theme.primaryColor
                : isClosed
                    ? AppColors.grey200
                    : AppColors.grey300,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dayLabel,
              style: ResponsiveHelper.tinyStyle(context).copyWith(
                // [DU1-F2] 선택 칩 글자 — 흰 85%(4.50)·80%(4.18) → 불투명 흰(5.58)
                color: isSelected ? Colors.white : weekdayColor,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 2)),
            Text(
              '${date.month}/${date.day}',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Colors.white
                    : isClosed
                        ? AppColors.grey400
                        : AppColors.textPrimary,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 3)),
            Text(
              // [DU1-R2d] 표시 수 = 그날 전체 업무 수(헤더와 같은 범위). 마감 판정(isClosed)은 마감 전 수(availableCount) 그대로
              isClosed ? '마감' : '업무 ${slot.workDetails.length}\u2060개', // 숫자·단위를 떼지 않는다
              style: ResponsiveHelper.tinyStyle(context).copyWith(
                color: isSelected
                    ? Colors.white
                    : isClosed
                        ? AppColors.grey400
                        : theme.primaryColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ── 4. 업무 목록 ──────────────────────────────

  Widget _buildWorkSection(BuildContext context) {
    final s = _gutter(context);
    final workDetails = _currentWorkDetails;
    final currentSlot = _currentSlot;

    // [INVITE-CAPACITY] 위와 같은 이유로 슬롯 공고는 공고 합계로 폴백하지 않는다.
    final slotReq = currentSlot?.workDetails.fold<int>(0, (a, wd) => a + wd.requiredCount)
        ?? widget.slotTotalRequired ?? (_to!.isFlexType ? 0 : _to!.totalRequired);
    final slotConf = currentSlot?.confirmedCount
        ?? widget.slotConfirmedCount ?? (_to!.isFlexType ? 0 : _to!.totalConfirmed);
    final isOverallClosed = _to!.isClosed || (slotReq > 0 && slotConf >= slotReq);

    // 날짜 헤더 텍스트
    String sectionTitle = '업무 목록';
    if (_selectedSlotDate != null && _to!.isFlexType) {
      final weekDays = ['월', '화', '수', '목', '금', '토', '일'];
      final d = FormatHelper.toKstDate(_selectedSlotDate!);
      final dayStr = weekDays[d.weekday - 1];
      // [DU1-F4] 이 수는 '본인이 지금 지원 가능한 업무'가 아니다(기지원·확정·FULL 포함) — 범위 그대로 '업무 N개'.
      // 날짜 헤더는 공백 단위로 자연 줄바꿈된다 — keepWords(결합 문자)를 넣지 않는다(검색·읽기 문자열 보존)
      sectionTitle = '${d.month}월 ${d.day}일($dayStr) · 업무 ${workDetails.length}\u2060개'; // 숫자·단위를 떼지 않는다('1|개')
    }

    // [CP05] 정밀 §8 — 표면 밖 섹션 제목 20/700, 장식 아이콘 없음. 제목→카드 12, 섹션 사이 24.
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(s, ConceptSpace.sectionGap, s, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sectionTitle,
            // [DU1] 날짜·업무 수는 판단 정보 — 320dp·2.0 에서 말줄임(업…) 대신 자연 줄바꿈
            style: ConceptText.section(),
          ),
          const SizedBox(height: ConceptSpace.sectionTitleToCard),
          if (workDetails.isEmpty)
            _buildEmptyWorkState(context)
          else
            ...workDetails.map((wd) => _buildWorkCard(
                  context,
                  work: wd,
                  slot: currentSlot,
                  isOverallClosed: isOverallClosed,
                )),
        ],
      ),
    );
  }

  Widget _buildEmptyWorkState(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 32)),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        children: [
          Icon(Icons.work_off_outlined, size: 40, color: AppColors.grey300),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text(
            _to!.isFlexType && _selectedSlotDate != null
                ? '해당 날짜의 업무 정보가 없습니다'
                : '업무 정보를 불러오는 중...',
            style: ResponsiveHelper.smallStyle(context).copyWith(color: AppColors.grey400),
          ),
        ],
      ),
    );
  }

  /// [R7-P4.4E.7A] 이미 관계가 있는 근무에 보여주는 상태 칩.
  ///
  ///   신규 지원 affordance(`선택`/`선택됨`)를 대신한다. 누를 수 없다 —
  ///   여기서 할 수 있는 일이 없기 때문이다. 상태 낱말은 새로 만들지 않고
  ///   기존 지원 UI(`WorkSelectionCard`)의 `확정` · `지원완료` 를 쓴다.
  /// [R7-APPLICATION-LIFECYCLE.1C] 확정 일정 겹침 — 이유가 보이는 chip.
  ///
  ///   색만으로 상태를 말하지 않는다(문구 + 아이콘). `마감` 과 다른 상태다 —
  ///   정원이 찬 것이 아니라 **내 일정**이 겹친 것이므로 문구도 달라야 한다.
  ///   "이미 지원한 일정" 도 아니다 — 관심이 아니라 약속이 이유다.
  Widget _buildConflictChip(
      BuildContext context, CommitmentConflictDecision conflict) {
    final unknown = conflict.isUnknown;
    final color = unknown ? AppColors.grey600 : AppColors.errorDark;
    final label = unknown ? '확인 필요' : '일정 겹침';
    final icon = unknown ? Icons.help_outline : Icons.event_busy_outlined;

    return Tooltip(
      message: unknown
          ? '내 일정을 확인할 수 없어요. 지원하기 전에 다시 확인해주세요.'
          : _conflictReason(conflict),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 8),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            // 좁은 폭·큰 배율에서 줄을 바꿔 전체를 보여준다.
            Flexible(
              child: Text(
                label,
                style: ResponsiveHelper.tinyStyle(context)
                    .copyWith(color: color, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 겹침 이유 한 줄. 시간·사업장은 **근로자 자신의** 일정이다.
  String _conflictReason(CommitmentConflictDecision conflict) {
    final time = conflict.conflictTime;
    final biz = conflict.conflictBusinessName;
    if (time == null) return '확정된 일정과 시간이 겹쳐 지원할 수 없어요.';
    if (biz == null) {
      return '확정된 일정($time)과 시간이 겹쳐 지원할 수 없어요.';
    }
    return '확정된 일정($biz $time)과 시간이 겹쳐 지원할 수 없어요.';
  }

  Widget _buildRelationChip(BuildContext context, WorkApplyRelation relation) {
    final (String label, IconData icon, Color color) = switch (relation) {
      WorkApplyRelation.confirmed ||
      WorkApplyRelation.contractPending =>
        ('확정', Icons.verified_outlined, AppColors.success),
      WorkApplyRelation.pending =>
        ('지원완료', Icons.check_circle_outline, AppColors.infoDark),
      // 초대는 수락·거절로 답하는 것이지 다시 지원하는 것이 아니다.
      WorkApplyRelation.invited =>
        ('초대 확인', Icons.mail_outline, AppColors.warningDark),
      WorkApplyRelation.none => ('', Icons.circle, AppColors.grey400),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          // 좁은 폭·큰 배율에서 줄을 바꿔 전체를 보여준다.
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: ResponsiveHelper.tinyStyle(context, color: color)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── 업무 카드 ─────────────────────────────────

  Widget _buildWorkCard(
    BuildContext context, {
    required WorkDetailModel work,
    required SlotModel? slot,
    required bool isOverallClosed,
  }) {
    final theme = Theme.of(context);
    // [WORKTYPE-IDENTITY] 이름으로 찾지 않는다 — 같은 이름을 다시 쓴 다른 업무의 안내가 붙는다.
    final workType = WorkTypeGuideResolver.resolve(
      workTypeId: work.workTypeId,
      workTypeName: work.workType,
      catalog: _workTypeCatalog,
      businessId: (_to ?? widget.to)?.businessId ?? '',
      // 화면 모델의 createdAt 은 누락 시 현재 시각이다 — 저장 문서의 값만 쓴다.
      postedAt: (_to ?? widget.to)?.storedCreatedAt,
    );

    // [R7-4 C4] 정원 판독은 공통 owner 하나로 한다.
    //
    //   예전에는 `workDetailStats != null` 하나로 "안다"고 판정했다. 그런데
    //   map 이 있다는 것과 **이 업무가 그 map 안에 있다**는 것은 다른 사실이다.
    //   슬롯 stats 에 master 업무 정의를 맞대면 조회가 빗나가고, 그때
    //   `confirmed = 0` 으로 접히면서 자리가 다 찬 업무가 `잔여 N명`이 된다.
    final reading = WorkCapacityReading.read(work, widget.workDetailStats);
    final workRequired = work.requiredCount;
    // [SYSTEM-INTEGRATION-R2.4.1 §2] 잔여 좌석에서 대기(PENDING)를 빼지 않는다.
    //
    //   PENDING은 관심이고 INVITED는 제안이다. 자리를 차지하는 것은
    //   CONTRACT_PENDING과 CONFIRMED뿐이다 — 관리자 쪽 모든 표면이 이미 그렇게
    //   센다. 여기만 대기까지 빼서, 필요 5 · 확정 2 · 대기 2인 근무를 관리자는
    //   `3명 부족`이라 보고 지원자는 `잔여 1명`으로 봤다. 그러면 아직 세 자리가
    //   열려 있는데 지원자는 거의 찼다고 판단해 지원을 포기한다.
    //
    //   같은 entity, 같은 사건, 같은 truth.
    //   [R7-4 C4] 모르면 잔여를 말하지 않는다 — null 이다.
    final workAvailable = reading.remaining;
    final hasWorkStats = reading.isKnown;

    // 모르는 것을 마감이라고 하지 않는다. `isFull` 은 아는 경우에만 true 다.
    final isWorkFull = reading.isFull;
    final isTimeExpired = work.isTimeExpired;
    final isClosed = isOverallClosed || isWorkFull || isTimeExpired;

    final now = DateTime.now();
    // 마감임박: 잔여 1명 이하 OR 업무 시작 2시간 이내
    final isAlmostFull = hasWorkStats && workAvailable == 1;
    bool isNearStart = false;
    if (slot != null) {
      // [DU1 후속15 §2.5] slot.date 는 KST 자정 instant — 그 성분을 기기 local 로 읽으면 KST 가 아닌 기기(·시험)에서
      //   전날로 해석돼 내일 근무가 '마감임박'이 됐다. KST 달력일 + KST 벽시계로 절대 시각을 만든다(2시간 규칙은 그대로).
      final startDt = FormatHelper.kstWallClockInstant(FormatHelper.toKstDate(slot.date), work.startTime);
      if (startDt != null) {
        final diffMins = startDt.difference(now).inMinutes;
        isNearStart = diffMins >= 0 && diffMins <= 120;
      }
    }
    final isDeadlineSoon = !isClosed && (isAlmostFull || isNearStart);

    // [R7-P1-2] 모집중 = 진행. green 은 달성에 남긴다.
    final (badgeLabel, badgeColor) = isClosed
        ? ('마감', AppColors.grey500)
        : isDeadlineSoon
            ? ('마감임박', AppColors.warning)
            : ('모집중', AppColors.infoMedium);

    // 이미지 유무로 레이아웃 분기 (16:9 대형 이미지 금지)
    final hasImage = workType?.thumbnailUrl != null;
    final isSelected = _isWorkSelected(work);
    // [R7-P4.4E.7A] 이미 관계가 있는 근무는 신규 선택 후보가 아니다.
    final relation = _relationFor(work, slot);
    // [R7-APPLICATION-LIFECYCLE.1C] 확정 일정과 겹치면 선택 후보가 아니다.
    final conflict = _commitmentConflictFor(work, slot);
    final canSelect = widget.mode == TODetailMode.applicant &&
        !isClosed &&
        !relation.blocksNewApplication &&
        !conflict.blocksNewApplication;
    // 업무 카드와 상세보기는 그대로 둔다 — 사용자는 한 공고에서 '이미 지원한
    // 업무' 와 '아직 지원하지 않은 업무' 를 나란히 비교해야 한다.
    final showRelation = widget.mode == TODetailMode.applicant &&
        relation.blocksNewApplication;
    // 관계 chip 이 이미 더 정확한 사실을 말하는 자리에는 겹침을 덧붙이지
    //   않는다(이미 지원·확정한 근무는 겹침 이전에 그 관계가 이유다).
    //   마감도 겹침보다 앞선다 — 공개 정원 상태가 개인 상태보다 먼저다.
    final showConflict = widget.mode == TODetailMode.applicant &&
        !isClosed &&
        !relation.blocksNewApplication &&
        (conflict.blocksNewApplication || conflict.isUnknown);

    // [CP05] 선택 의미 node 와 물리 버튼이 **같은 콜백 객체**를 쓴다(의미 tap == 실제 동작).
    void toggle() => _toggleWork(work, slot);
    // [CP05] 정밀 §8·§9 — 업무별 시간 20/700(시안처럼 범위는 en dash), 휴게·실근무는 같은 덩어리의 메타 14.
    final timeText = '${work.startTime}–${work.endTime}';
    final breakText = _breakTimeStr(work);
    final netText = _netTimeKorean(work);
    // [CP05] 정밀 §6·§8 conceptValue — 출처가 확정된 **이 업무의** 요율만 크게(30/700 brand, 단위 16/700).
    //   새 예상 총액·공제/수당 계산 0. 숫자·단위는 기존 formattedWage 문자열을 표시만 둘로 나눈다(의미 이름은 원문).
    final wageText = work.formattedWage;
    final wageHasUnit = wageText.endsWith('원');
    final wageNumber = wageHasUnit ? wageText.substring(0, wageText.length - 1) : wageText;
    final sched = work.payScheduleTypeLabel;
    final wageLabel = sched.isNotEmpty ? '${work.wageTypeLabel} · $sched' : work.wageTypeLabel;

    return Container(
      margin: const EdgeInsets.only(bottom: ConceptSpace.cardGap),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.primaryColor.withValues(alpha: 0.03)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        // [DU1 후속36 §2 S041] 업무 카드가 세로로 반복되며 회색 테두리가 화면 밀도를 높였다 — 미선택은 더 옅은 경계,
        //   선택은 brand 1.5 그대로(선택 의미는 테두리 색·두께가 맡는다).
        border: Border.all(
          color: isSelected ? theme.primaryColor : AppColors.borderLight,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(ConceptSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 메인 콘텐츠 행 ─────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 좌: 업무 썸네일 (이미지 있을 때만, 없으면 영역 자체 제거)
                if (hasImage) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 88,
                      height: 88,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ImageHelper.buildCachedImage(
                            workType!.thumbnailUrl!,
                            fit: BoxFit.cover,
                            memCacheWidth: 264,
                            fadeInDuration: const Duration(milliseconds: 150),
                          ),
                          if (isClosed)
                            Container(
                                color: Colors.black.withValues(alpha: 0.28)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],

                // 우: 업무 정보 (이미지 없으면 전체 너비)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 업무명 + 상태 배지
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              work.workType,
                              // [CP05] 정밀 §8 업무·본문 16, 굵기 700. 닫힘은 중립 글자.
                              style: ConceptText.body(
                                color: isClosed
                                    ? AppColors.textSecondary
                                    : AppColors.textPrimary,
                              ).copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // [DU-VQ-02 · 후속14] 보통 '모집중'은 상단 공고 상태가 이미 말한다 — 업무마다 같은 알약을 반복하면
                          //   시간·임금보다 먼저 읽혔다. 업무별 상태 계산은 그대로 두고 **보통 모집중만** 약한 텍스트로 낮춘다.
                          //   마감임박·마감은 알약 그대로(계속 읽혀야 하는 사유).
                          if (!isClosed && !isDeadlineSoon)
                            Text(
                              badgeLabel,
                              style: ConceptText.meta(),
                            )
                          else
                            // [CP05] 정밀 §4·§8 — 상태 필 13/700 H10/V4 r8. 마감임박 warningBg/Dark, 마감은 중립(선택불가 ≠ 오류).
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: badgeColor == AppColors.warning
                                    ? AppColors.warningBg
                                    : AppColors.grey100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                badgeLabel,
                                style: ConceptText.pill(badgeColor == AppColors.warning
                                    ? AppColors.warningDark
                                    : AppColors.textSecondary),
                              ),
                            ),
                        ],
                      ),

                      // 한줄 업무 설명
                      // [CP05] 말줄임 없이 메타 14 로 전문(업무 안내 원문 그대로).
                      if (workType?.description != null &&
                          workType!.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          workType.description!,
                          style: ConceptText.meta(),
                        ),
                      ],

                      const SizedBox(height: 8),

                      // 근무시간 — [CP05] 업무별 시간 20/700
                      Text(
                        TextLayout.keepWords(timeText),
                        semanticsLabel: timeText,
                        style: ConceptText.adminWorkTime().copyWith(
                            color: isClosed ? AppColors.textSecondary : AppColors.textPrimary),
                      ),
                      if (breakText.isNotEmpty || netText.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 2,
                          children: [
                            if (breakText.isNotEmpty)
                              Text(breakText, style: ConceptText.meta()),
                            if (netText.isNotEmpty)
                              Text(
                                '실근무 ${_netTimeKorean(work)}',
                                style: ConceptText.meta().copyWith(color: AppColors.textSecondary),
                                // [DU1-F2] 읽어야 하는 조건 — 비활성 회색(grey400) 대신 보조 글자색
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: ConceptSpace.infoGroupGap),

            // 급여 — [CP05] conceptValue(#EEF2FF r16, 테두리·그림자 0). 시간 다음 요율(시안 순서).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(ConceptSpace.cardPadding),
              decoration: ConceptSurface.value(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TextLayout.keepWords(wageLabel),
                    semanticsLabel: wageLabel,
                    style: ConceptText.infoLabel(),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(children: [
                      // 숫자 안에서 줄을 바꾸지 않는다(낱말 묶음) — 좁으면 숫자와 단위 사이에서만 내려간다.
                      TextSpan(text: TextLayout.keepWords(wageNumber), style: ConceptText.detailRate()),
                      if (wageHasUnit)
                        TextSpan(text: '원', style: ConceptText.detailRateUnit()),
                    ]),
                    semanticsLabel: '${work.wageTypeLabel} ${work.formattedWage}',
                  ),
                  // 세금 공제 — 낮은 우선순위 (보조 정보)
                  if (work.taxDeductionType != InsuranceRateModel.typeNone) ...[
                    const SizedBox(height: 4),
                    Text(
                      InsuranceRateModel.typeLabel(work.taxDeductionType),
                      style: ConceptText.meta().copyWith(color: AppColors.textSecondary),
                      // [DU1-F2] 공제 방식은 실수령에 영향 — 읽을 수 있는 대비
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: ConceptSpace.infoGroupGap),

            // 모집인원 — 지원자 관점: 모집 n명 · 잔여 n명
            // [CP05] 정밀 §4 — 잔여 수는 중립 굵은 글자, 자리가 다 찬 `마감`은 중립(선택불가 ≠ 오류, 빨강 0).
            RichText(
              textScaler: MediaQuery.textScalerOf(context), // [SCALE-BALANCE.34] RichText 는 배율을 스스로 받지 않는다
              text: TextSpan(
                // RichText 는 DefaultTextStyle(앱 글꼴)을 병합하지 않는다 — 원 코드(ResponsiveHelper.tinyStyle)처럼 글꼴을 명시한다.
                style: ConceptText.meta().copyWith(fontFamily: 'NotoSansKR'),
                children: [
                  const TextSpan(text: '모집 '),
                  TextSpan(
                    text: '$workRequired명',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  if (workAvailable != null) ...[
                    const TextSpan(text: ' · 잔여 '),
                    TextSpan(
                      // [R2.4.1 §2] 잔여 0은 자리가 다 찼다는 뜻이다.
                      //   예전에는 대기자 수까지 빼서 0이 될 수 있었고,
                      //   그때 `대기중`이라고 얼버무렸다. 이제 0은
                      //   확정이 정원에 닿았다는 사실 하나뿐이다.
                      text: workAvailable > 0
                          ? '$workAvailable명'
                          : '마감',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: workAvailable > 0
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // [DU-VQ-02 · 후속16 §4] 본문/버튼 사이 내부 구분선 제거 — 카드 안 선이 정보를 한 번 더 끊었다.
            //   카드 테두리·버튼 행 padding 이 이미 구획을 만든다.

            // ── 버튼 행 ────────────────────────────
            // [CP05] 보조·선택 receiver ≥48(실제 버튼 최소 높이), 선택 버튼은 업무 이름·선택 상태를 가진 의미 node 하나.
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  // [DU-VQ-02 · 후속15] 상세보기는 보조 — 선택(brand 테두리)과 같은 테두리 버튼이라 주·보조가 구별되지 않았다
                  child: TextButton.icon(
                    onPressed: () =>
                        _showWorkTypeDetail(context, work, workType),
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: Text(TextLayout.keepWords('업무 자세히 보기'),
                        semanticsLabel: '업무 자세히 보기'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      minimumSize: const Size(ConceptSpace.minTouch, ConceptSpace.minTouch),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      textStyle: ConceptText.meta().copyWith(fontFamily: 'NotoSansKR', fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                // [R7-P4.4E.7A] 관계가 있으면 신규 지원 affordance 대신
                //   지금 관계를 말한다. vocabulary 는 기존 지원 UI 와 맞춘다.
                if (showRelation) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildRelationChip(context, relation),
                  ),
                ],
                // [R7-APPLICATION-LIFECYCLE.1C] 관계는 없는데 지원할 수 없는
                //   경우 — 이 시간에 내 **다른** 약속이 있다. 이유를 말하지
                //   않고 버튼만 지우면 사용자는 앱이 고장났다고 생각한다.
                if (showConflict) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildConflictChip(context, conflict),
                  ),
                ],
                if (canSelect) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      container: true,
                      button: true,
                      selected: isSelected,
                      label: '${work.workType} ${isSelected ? '선택됨' : '선택'}',
                      excludeSemantics: true,
                      onTap: toggle,
                      child: isSelected
                        ? ElevatedButton.icon(
                            onPressed: toggle,
                            icon: const Icon(Icons.check_circle, size: 18),
                            label: const Text('선택됨'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.primaryColor,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(ConceptSpace.minTouch, ConceptSpace.minTouch),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              textStyle: ConceptText.meta().copyWith(fontFamily: 'NotoSansKR', fontWeight: FontWeight.w700),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: toggle,
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: const Text('선택'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.primaryColor,
                              side: BorderSide(color: theme.primaryColor),
                              minimumSize: const Size(ConceptSpace.minTouch, ConceptSpace.minTouch),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              textStyle: ConceptText.meta().copyWith(fontFamily: 'NotoSansKR', fontWeight: FontWeight.w700),
                            ),
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 5. 준비사항 (칩 형태) ─────────────────────

  /// [R7-PAYROLL-POLICY.4 §33] 근태·급여 처리 기준 고지.
  ///
  ///   근로자 화면에 숫자 7개를 모두 펼치지 않는다 — 한 줄로 **존재와 영향**을
  ///   말하고, 실제 숫자는 상세에서 본다.
  ///
  ///   여기 표시하는 값은 이 사업장의 **현재 기준**이다. 지원하면 그 시점의
  ///   기준이 지원서에 고정되고(서버가 `attendancePolicySnapshot` 으로 적는다),
  ///   사업장이 그 뒤에 기준을 바꿔도 이미 한 지원에는 소급되지 않는다.
  ///   읽기를 새로 하지 않는다 — 이미 불러온 사업장 문서를 쓴다.
  Widget _buildAttendancePolicyDisclosure(BuildContext context) {
    // [ATTENDANCE-RULE-GUIDE.29-A1] 핵심 기준을 처음부터 보인다(예전에는 한 줄 + '상세 기준' 시트 안에만
    //   숫자가 있었다). 사례는 '시간 예시 보기' 로 편다.
    //   값의 출처: 내 지원(초대·지원·확정)에서 들어오면 **그 지원서에 고정된 기준(snapshot)**과 그 근무 시각,
    //   일자리 찾기에서 들어오면 이 사업장의 **현재 기준**과 지금 보이는 근무 정의의 첫 근무 시각.
    //   기기 대조: 사업장 기준을 바꾼 뒤 초대 상세가 현재 기준(10분)을 보여 수락 확인창(snapshot 5분)과 달랐다.
    //   snapshot 이 없는 지원서면 현재 기준으로 채우지 않는다(기록 없음 안내). 새 조회 없음.
    final mine = widget.myApplication;
    final rules = mine != null ? mine.attendancePolicySnapshot : _business!.attendanceRules;
    final s = _gutter(context);
    final wd = _currentWorkDetails.firstOrNull;
    final start = mine?.startTime ?? wd?.startTime;
    final end = mine?.endTime ?? wd?.endTime;
    // [CP05] 정밀 §8 — 섹션 제목 20/700(장식 아이콘 없음), 기준 고지 문장은 정책 고지 원문 그대로(문구 변경 제외)이고
    //   글자만 메타 14(중요 조건을 13 이하로 줄이지 않는다).
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(s, ConceptSpace.sectionGap, s, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(kAttendanceRuleGuideTitle),
          const SizedBox(height: ConceptSpace.sectionTitleToCard),
          if (rules != null) ...[
            AttendanceRuleGuideView(
              guide: attendanceRuleGuide(rules, startHHmm: start, endHHmm: end),
              collapsibleExamples: true,
              workTimeLabel: mine != null ? '근무시간' : '예시 기준 근무',
            ),
            const SizedBox(height: 8),
            Text(kAttendancePolicyEffectNote,
                style: ConceptText.meta().copyWith(color: AppColors.grey700)),
            const SizedBox(height: 4),
            Text(
              mine != null
                  ? kAttendancePolicyFrozenNote
                  : '지원하면 이 기준이 지원 시점 조건으로 고정됩니다. '
                      '사업장이 이후에 기준을 바꿔도 이미 한 지원에는 적용되지 않습니다.',
              style: ConceptText.meta(),
            ),
          ] else
            Text(
                mine != null
                    ? kAttendancePolicyUnknownNote
                    : '출퇴근 시각은 사업장의 처리 기준에 따라 계산됩니다.',
                style: ConceptText.meta().copyWith(color: AppColors.grey700)),
        ],
      ),
    );
  }

  Widget _buildPrecautionsSection(BuildContext context) {
    final s = _gutter(context);
    final raw = _business!.precautions!;

    // 줄바꿈 기준으로 split → 칩 목록
    final items = raw
        .split(RegExp(r'[\n]'))
        .map((e) => e.trim().replaceAll(RegExp(r'^[·•\-\*]\s*'), ''))
        .where((e) => e.isNotEmpty)
        .toList();

    // [CP05] 정밀 §8 상세 정보행 — 준비사항의 실제 값을 행으로 보인다(아이콘 18 #25325B, 뒤 12, 값 16, 수직 12).
    //   필수 항목(필수/필히/반드시/꼭)은 기존처럼 경고 진한 글자·굵게·느낌표 아이콘으로 구별한다(빨강 아님). 내용 삭제·축약 0.
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(s, ConceptSpace.sectionGap, s, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          _sectionTitle('준비사항'),
          const SizedBox(height: 4),

          // 필수 항목(필수/필히/반드시/꼭) warningDark, 일반 항목 본문색
          if (items.length <= 6)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) _infoDivider(context),
                  Builder(builder: (context) {
                    final item = items[i];
                    final isRequired = item.contains('필수') ||
                        item.contains('필히') ||
                        item.contains('반드시') ||
                        item.contains('꼭');
                    return _buildInfoRow(
                      context,
                      icon: isRequired
                          ? Icons.priority_high_rounded
                          : Icons.check_circle_outline,
                      iconColor: isRequired ? AppColors.warningDark : AppColors.conceptNavy,
                      value: item,
                      valueStyle: isRequired
                          ? ConceptText.infoValue().copyWith(
                              color: AppColors.warningDark, fontWeight: FontWeight.w700)
                          : null,
                    );
                  }),
                ],
              ],
            )
          else
            // 항목이 많으면 텍스트로
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                raw,
                style: ConceptText.body(),
              ),
            ),
        ],
      ),
    );
  }

  /// [CP05] 정밀 §8 상세 정보행 사이 구분선 — #F1F3F5, 1 physical px.
  Widget _infoDivider(BuildContext context) {
    final px = 1 / MediaQuery.devicePixelRatioOf(context);
    return Divider(height: px, thickness: px, color: AppColors.conceptDivider);
  }

  /// [CP05] 정밀 §8 상세 정보행 — 아이콘 18(outlined, 기본 #25325B) · 뒤 12 · 라벨 14/400 · 값 16/400 · 수직 padding 12.
  ///   값은 실제 값 그대로(미상값을 '없음'으로 바꾸지 않는다). 이동·복사·전화 같은 행동이 있으면 오른쪽에 receiver 48 하나.
  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    String? label,
    required String value,
    String? sub,
    Color? iconColor,
    TextStyle? valueStyle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: iconColor ?? AppColors.conceptNavy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (label != null) ...[
                  Text(TextLayout.keepWords(label), semanticsLabel: label, style: ConceptText.infoLabel()),
                  const SizedBox(height: 2),
                ],
                Text(value, style: valueStyle ?? ConceptText.infoValue()),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: ConceptText.meta()),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  // ── 6. 시설 및 환경 ───────────────────────────

  Widget _buildFacilitiesSection(BuildContext context) {
    final hasFacilities = _business!.parkingAvailable ||
        (_business!.mealsProvided?.isNotEmpty == true) ||
        _business!.uniformProvided != null ||
        (_business!.facilities?.isNotEmpty == true);
    if (!hasFacilities) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final s = _gutter(context);

    // 칩 데이터 생성
    final chips = <({IconData icon, String label, bool positive})>[];
    chips.add((
      icon: Icons.local_parking,
      label: _business!.parkingAvailable ? '주차 가능' : '주차 불가',
      positive: _business!.parkingAvailable,
    ));
    if (_business!.mealsProvided?.isNotEmpty == true) {
      chips.add((
        icon: Icons.restaurant,
        label: '${_business!.mealsProvided!.join(', ')} 제공',
        positive: true,
      ));
    }
    if (_business!.uniformProvided != null) {
      chips.add((
        icon: Icons.checkroom,
        label: '유니폼 ${_business!.uniformProvided}',
        positive: _business!.uniformProvided != '없음',
      ));
    }
    if (_business!.facilities?.isNotEmpty == true) {
      chips.add((
        icon: Icons.weekend,
        label: '편의 ${_business!.facilities!.join('/')}',
        positive: true,
      ));
    }
    if (chips.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(s, ConceptSpace.sectionGap, s, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('시설 및 환경'),
          const SizedBox(height: ConceptSpace.sectionTitleToCard),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips.map((c) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: c.positive
                    ? theme.primaryColor.withValues(alpha: 0.07)
                    : AppColors.grey100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: c.positive
                      ? theme.primaryColor.withValues(alpha: 0.2)
                      : AppColors.grey200,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(c.icon,
                      size: 14,
                      color: c.positive ? theme.primaryColor : AppColors.grey400),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      c.label,
                      style: ConceptText.meta().copyWith(
                        color: c.positive ? AppColors.grey800 : AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // ── 7. 찾아오는 길 ────────────────────────────

  Widget _buildTransportSection(BuildContext context) {
    final theme = Theme.of(context);
    final s = _gutter(context);
    // [CP05] 정밀 §8·§9 — 기존 주소·연락처·교통·사진·지도를 그대로 두고 표시만 상세 정보행(라벨 14·값 16·아이콘 18)과
    //   #F1F3F5 구분선으로 바꾼다. 복사·전화·큰 지도 행동과 지도 생성 조건은 그대로다.
    final rows = <Widget>[
      _buildInfoRow(
        context,
        icon: Icons.place_outlined,
        label: '근무 장소',
        value: _business!.address,
        sub: _business!.detailAddress,
        trailing: IconButton(
          onPressed: () {
            final addr = _business!.detailAddress != null
                ? '${_business!.address} ${_business!.detailAddress}'
                : _business!.address;
            Clipboard.setData(ClipboardData(text: addr));
            ToastHelper.showSuccess('주소가 복사되었습니다');
          },
          icon: Icon(Icons.copy, size: 18, color: theme.primaryColor),
          tooltip: '주소 복사',
        ),
      ),
      if (_business!.phone != null)
        _buildInfoRow(
          context,
          icon: Icons.phone_outlined,
          label: '연락처',
          value: FormatHelper.formatPhone(_business!.phone!),
          trailing: IconButton(
            onPressed: () => _callPhone(_business!.phone!),
            icon: Icon(Icons.call, size: 18, color: theme.primaryColor),
            tooltip: '전화 걸기',
          ),
        ),
      if (_business!.transportDescription != null)
        _buildInfoRow(context,
            icon: Icons.directions_outlined,
            label: '오시는 길',
            value: _business!.transportDescription!)
      else ...[
        if (_business!.nearestStation != null)
          _buildInfoRow(context,
              icon: Icons.subway_outlined,
              label: '가까운 역',
              value: _business!.nearestStation!,
              sub: _business!.walkingMinutes != null
                  ? '도보 ${_business!.walkingMinutes}분' : null),
        if (_business!.busInfo != null)
          _buildInfoRow(context,
              icon: Icons.directions_bus_outlined,
              label: '버스',
              value: _business!.busInfo!),
      ],
    ];
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(s, ConceptSpace.sectionGap, s, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('찾아오는 길'),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) _infoDivider(context),
            rows[i],
          ],
          if (_business!.transportImageUrls != null &&
              _business!.transportImageUrls!.isNotEmpty) ...[
            const SizedBox(height: ConceptSpace.infoGroupGap),
            LayoutBuilder(builder: (ctx2, constraints) {
              final urls = _business!.transportImageUrls!;
              const gap = 8.0;
              // 3장 이상이면 2.4장이 보이도록 너비 계산 → 마지막 이미지가 살짝 잘려 스크롤 가능 암시
              // 1~2장이면 고정 100으로 그냥 표시
              final itemW = urls.length >= 3
                  ? (constraints.maxWidth - gap * 2) / 2.4
                  : 100.0;
              return SizedBox(
                height: itemW,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: urls.length,
                  itemBuilder: (ctx, i) => GestureDetector(
                    onTap: () => CommonWidgets.showImagePreview(
                      context, urls, initialIndex: i),
                    child: Container(
                      width: itemW, height: itemW,
                      margin: const EdgeInsets.only(right: gap),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: ImageHelper.buildCachedImage(
                          urls[i],
                          width: itemW, height: itemW,
                          fit: BoxFit.cover, memCacheWidth: 300,
                          fadeInDuration: const Duration(milliseconds: 150),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
          if (_business!.latitude != null && _business!.longitude != null) ...[
            const SizedBox(height: ConceptSpace.infoGroupGap),
            RepaintBoundary(
              child: GestureDetector(
                onTap: () => _showFullMap(context),
                child: SizedBox(
                  height: 180,
                  // [.20 PERCEIVED-PERFORMANCE] 지도는 화면 맨 아래다. 진입 즉시 WebView 를
                  //   만들면 첫 생성이 상세 진입을 1~2초 멈췄다 — 스크롤로 다가올 때 만든다.
                  child: DeferUntilOnScreen(
                    placeholder: Container(
                      decoration: BoxDecoration(
                        color: AppColors.grey100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.map_outlined, color: AppColors.grey400, size: 32),
                    ),
                    child: KakaoMapWidget(
                      latitude: _business!.latitude!,
                      longitude: _business!.longitude!,
                      placeName: _business!.name,
                      showControls: false,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => _showFullMap(context),
                icon: const Icon(Icons.zoom_out_map, size: 18),
                label: Text('큰 지도 보기',
                    style: ResponsiveHelper.bodyStyle(context)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 하단 버튼 바 ──────────────────────────────

  Widget _buildBottomBar(BuildContext context) {
    final theme = Theme.of(context);
    final isClosed = _isEffectivelyClosed;
    final count = _totalSelectedCount;

    // 관리자 미리보기: 하단 닫기 버튼 제거 (앱바 뒤로가기로 충분)
    if (widget.mode == TODetailMode.adminPreview) {
      return const SizedBox.shrink();
    }

    // 내 지원에서 진입: Application 상태에 맞는 CTA (마감된 공고 버튼 없음)
    if (widget.myApplication != null) {
      return _buildApplicationBottomBar(context);
    }

    // 버튼 텍스트 & 활성 여부
    final String buttonText;
    final bool isDisabled;
    // 서류 미완료 차단 여부 — 신분증·통장 관련만 바텀시트로 안내
    final bool isDocumentBlock = !isClosed && !_isApplyable && _isDocumentBlocked;

    if (isClosed) {
      // [INVITE-CAPACITY] 인원이 찬 것은 공고가 끝난 것이 아니다(취소가 나오면 다시 열린다).
      // [CP05] Q6 버튼·상태 — 해요체로 통일(같은 바의 `모집 인원이 찼어요`와 같은 말투).
      buttonText = _closedByCapacityOnly ? '모집 인원이 찼어요' : '마감된 공고예요';
      isDisabled = true;
    } else if (isDocumentBlock) {
      // 서류 미완료: 버튼 활성 유지 → 탭 시 지원 준비 바텀시트
      buttonText = '지원 준비하기';
      isDisabled = false;
    } else if (!_isApplyable) {
      // 블랙리스트·페널티·본인인증 차단: 기존대로 버튼 비활성
      buttonText = _applyBlockReason ?? '지원 불가';
      isDisabled = true;
    } else if (_isApplying) {
      buttonText = '처리 중...';
      isDisabled = true;
    } else if (count == 0) {
      // [ISG2-CTA] 고를 것이 있을 때만 고르라고 한다.
      buttonText = _hasSelectableWork
          ? '지원할 업무를 선택해 주세요'
          : '지금 지원할 수 있는 업무가 없어요';
      isDisabled = true;
    } else {
      // [DU1-F3] 320dp·2.0 에서 '지원하/기'로 끊겼다 — 버튼은 행동만, 선택 수는 위 줄(selectionNote)
      buttonText = '지원하기';
      isDisabled = false;
    }

    // [CP05] 정밀 §8 — 하단 주행동 바: 좌우 gutter, 주CTA 16/700 최소 52·r12(내용이 늘면 자연 높이), 선택 수 메타 14.
    final g = _gutter(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(g, 12, g, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          if (!isDisabled && !_isApplying && count > 0 && _applyBlockReason == null) ...[
            Text('$count개 업무 선택됨',
                textAlign: TextAlign.center,
                style: ConceptText.meta().copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
          ],
          SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isDisabled
                ? null
                : (isDocumentBlock
                    ? () => _showDocumentReadinessSheet(context)
                    : _showConfirmAndApply),
            style: ElevatedButton.styleFrom(
              // 서류 미완료: 연한 파란 배경 + 진한 파란 텍스트 (경고색 사용 안 함)
              backgroundColor: isDisabled
                  ? null
                  : (isDocumentBlock ? AppColors.infoBg : theme.primaryColor),
              foregroundColor: isDisabled
                  ? null
                  : (isDocumentBlock ? AppColors.infoDark : Colors.white),
              disabledBackgroundColor: AppColors.grey100,
              disabledForegroundColor: AppColors.grey400,
              // [DU1-F7] 주 행동 최소 높이 52(글자 배율이 크면 늘어난다)
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              textStyle: ConceptText.button().copyWith(fontFamily: 'NotoSansKR'),
            ),
            child: _isApplying
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('처리 중'),
                    ],
                  )
                // [DU1] 비활성 안내 문구의 320dp·2.0 음절 끊김은 잔여(시험이 문구 정확 일치로 버튼을 찾는다 — 정규화 후 처리)
                // [CP05] 주행동 글자는 낱말 단위로만 줄을 바꾼다(B 에서 `선택해 주/세요` 같은 음절 끊김 0). 의미 이름은 원문.
                : Text(TextLayout.keepWords(buttonText),
                    semanticsLabel: buttonText, textAlign: TextAlign.center),
          ),
          ),
          ],
        ),
      ),
    );
  }

  // ── 지원 준비 바텀시트 ─────────────────────────

  /// 서류 미완료 상태에서 '지원 준비하기' 버튼 탭 시 표시하는 바텀시트.
  /// 신분 확인(①)·급여정보(②) 완료 여부를 체크 상태로 표시하고
  /// '지원 준비하기' → DocumentManagementScreen 으로 이동.
  void _showDocumentReadinessSheet(BuildContext context) {
    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;

    // (idCardImagePath 신규 flow + idCardImageUrl legacy 양쪽 허용)
    final hasId = user.hasIdDocument;
    // [PII-DOC-R1.5.4] 급여정보 줄 복구 — 계좌 3필드 + 통장사본 등록 여부.
    //   canonical getter를 쓴다(예전 인라인 계산은 accountHolder를 빠뜨렸다).
    final hasWage = user.hasBankAccount && user.hasBankbookDocument;

    DialogHelper.showSheet<void>(
      context,
      useRootNavigator: true,
      // [DU279 PS12] 320·2.0 에서 내용이 아래로 246px 넘쳐 '지원 준비하기'·'나중에'가 화면 밖이었다 —
      //   내용 높이만큼 열고(isScrollControlled), 넘치면 스크롤한다.
      isScrollControlled: true,
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 24),
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // [DU279 PS1·PS13] 본문색, 낱말 단위(B320 '필요해/요'). 읽기 이름은 원문.
            Text(TextLayout.keepWords('지원 준비가 필요해요'),
                semanticsLabel: '지원 준비가 필요해요',
                style: ResponsiveHelper.subtitleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(TextLayout.keepWords('일자리에 지원하려면\n아래 정보를 먼저 등록해주세요.'),
                // [DU279 PS2] grey500(2.68) → 보조색, 낱말 단위(B320 '등록/해주세요')
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(color: AppColors.textSecondary, height: 1.5)),
            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
            _buildReadinessRow(context, '신분 확인', '신분증 등록', hasId),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildReadinessRow(context, '급여정보', '계좌 및 통장사본 등록', hasWage),
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const DocumentManagementScreen()),
                  );
                },
                // [DU279 PS4] 대표색 토큰·높이 52(공고 하단 CTA 와 같다)
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14)),
                  textStyle: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                child: const Text('지원 준비하기'),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                // [DU279 PS5] grey400(1.88) → 보조색, 터치 48. 스타일은 textStyle 로(Text style 이 전경색을 덮는다 — DU267)
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  minimumSize: const Size(48, 48),
                  textStyle: ResponsiveHelper.bodyStyle(context, fontWeight: FontWeight.w600),
                ),
                child: const Text('나중에'),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// 지원 준비 바텀시트의 항목 행 — 상태 아이콘 (! 미완료 / ✓ 완료)
  /// 빈 원(radio_button_unchecked)은 체크박스처럼 보이므로 상태 아이콘으로 명확히 구분
  Widget _buildReadinessRow(
      BuildContext context, String label, String sublabel, bool isDone) {
    // [DU279 PS3] 하드코딩 색(#22C55E 2.3·#9CA3AF 2.5) → 토큰. 완료 = successBg 원·successDark, 미완료 = grey100 원·보조색.
    final mark = isDone ? AppColors.successDark : AppColors.textSecondary;
    return Row(
      children: [
        // 상태 아이콘: 완료 = 체크 원, 미완료 = ! 원
        Container(
          width: ResponsiveHelper.iconSize(context, 24),
          height: ResponsiveHelper.iconSize(context, 24),
          decoration: BoxDecoration(
            color: isDone ? AppColors.successBg : AppColors.grey100,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isDone
                ? Icon(Icons.check_rounded,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: mark)
                : Text('!',
                    style: TextStyle(
                      fontSize: ResponsiveHelper.iconSize(context, 13),
                      fontWeight: FontWeight.w700,
                      color: mark,
                      height: 1.0,
                    )),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary)
                      .copyWith(fontWeight: FontWeight.w600)),
              Text(isDone ? '등록 완료' : '등록 필요',
                  style: ResponsiveHelper.smallStyle(context, color: mark)),
            ],
          ),
        ),
        if (isDone)
          Text('완료',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.successDark)
                  .copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ── Helper 위젯 ───────────────────────────────

  /// 순 근무시간을 한국어 형식으로 반환 (예: "8시간", "7시간 30분")
  String _netTimeKorean(WorkDetailModel work) {
    try {
      int toMins(String t) {
        final p = t.split(':');
        return int.parse(p[0]) * 60 + int.parse(p[1]);
      }
      int s = toMins(work.startTime);
      int e = toMins(work.endTime);
      if (e <= s) e += 1440;
      final net = (e - s - work.breakMinutes).clamp(0, 1440);
      if (net <= 0) return '';
      final h = net ~/ 60;
      final m = net % 60;
      if (m == 0) return '$h시간';
      if (h == 0) return '$m분';
      return '$h시간 $m분';
    } catch (_) {
      return '';
    }
  }

  /// 휴게시간 문자열 (예: "(휴게 1시간)", "(휴게 30분)")
  String _breakTimeStr(WorkDetailModel work) {
    final mins = work.breakMinutes;
    if (mins <= 0) return '';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h == 0) return '(휴게 $m분)';
    if (m == 0) return '(휴게 $h시간)';
    return '(휴게 $h시간 $m분)';
  }

  // ── 업무유형 상세 바텀시트 ──────────────────────

  // 업무 상세 바텀시트 — 순서: 업무명 → 한줄설명 → 이미지 → 업무상세 → 근무정보 → 급여 → 모집 → 조건
  // DraggableScrollableSheet는 backgroundColor:transparent 필수 → 직접 호출 허용 (CLAUDE.md 예외)
  // useRootNavigator:true → UserRootScreen의 BottomNavigationBar까지 Dim 처리
  void _showWorkTypeDetail(
      BuildContext context, WorkDetailModel work, BusinessWorkTypeModel? workType) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // 드래그 핸들
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: () {
                    final cp = ResponsiveHelper.cardPadding(context);
                    return EdgeInsets.fromLTRB(
                      cp.left, 4, cp.right,
                      max(cp.bottom, MediaQuery.viewPaddingOf(context).bottom),
                    );
                  }(),
                  children: [
                    // ── 1. 업무명 ──────────────────────────
                    // [DU279 PS6] 본문색, 식별 단위
                    Text(
                      TextLayout.identity(work.workType),
                      semanticsLabel: work.workType,
                      style: ResponsiveHelper.titleStyle(context)
                          .copyWith(fontWeight: FontWeight.bold, height: 1.3, color: AppColors.textPrimary),
                    ),

                    // ── 2. 한줄 설명 ────────────────────────
                    if (workType?.oneLineIntro != null &&
                        workType!.oneLineIntro!.isNotEmpty) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      // [DU279 PS7·PS14] grey600 → 보조색, 낱말 단위(W360 '일이에/요')
                      Text(
                        TextLayout.keepWords(workType.oneLineIntro!),
                        semanticsLabel: workType.oneLineIntro!,
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(color: AppColors.textSecondary, height: 1.4),
                      ),
                    ],

                    // ── 3. 업무 이미지 gallery (있을 때만, placeholder 금지) ──
                    if (workType != null &&
                        (workType.thumbnailUrl != null ||
                            workType.images?.isNotEmpty == true)) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      _buildWorkTypeImages(context, workType),
                    ],

                    // ── 3b. 업무 상세 설명 (이미지 뒤, 구분선 앞) ──
                    // 이미지 없음: 한줄설명 → 업무상세 → 구분선
                    // 이미지 있음: 한줄설명 → 이미지 → 업무상세 → 구분선
                    if (workType?.description != null &&
                        workType!.description!.isNotEmpty) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(
                            ResponsiveHelper.spacing(context, 14)),
                        // [DU279 PS8·PS14] 대표색 4% 면·10% 선 → 바탕색 면(선 없음), 낱말 단위
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          TextLayout.keepWords(workType.description!),
                          semanticsLabel: workType.description!,
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            height: 1.6,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],

                    // ── 구분선 ──────────────────────────────
                    SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                    const Divider(height: 1, color: AppColors.grey200),
                    SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                    // ── 근무 정보 ────────────────────────────
                    _buildInfoBlock(
                      context,
                      '근무 시간',
                      () {
                        final t = '${work.startTime} ~ ${work.endTime}';
                        final net = _netTimeKorean(work);
                        return net.isNotEmpty ? '$t  ·  실근무 $net' : t;
                      }(),
                    ),
                    if (_breakTimeStr(work).isNotEmpty) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        _breakTimeStr(work)
                            .replaceAll('(', '')
                            .replaceAll(')', ''),
                        style: ResponsiveHelper.smallStyle(context)
                            .copyWith(color: AppColors.textSecondary), // [DU279 PS10] grey500 2.68
                      ),
                    ],

                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                    // ── 급여 ────────────────────────────────
                    _buildInfoBlock(
                      context,
                      '급여',
                      () {
                        final base =
                            '${work.wageTypeLabel} ${work.formattedWage}';
                        final sched = work.payScheduleTypeLabel;
                        return sched.isNotEmpty ? '$base  ·  $sched' : base;
                      }(),
                      valueColor: AppColors.successDark,
                    ),
                    if (work.payScheduleDetail.isNotEmpty) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        '입금 예정  ${work.payScheduleDetail}',
                        style: ResponsiveHelper.smallStyle(context)
                            .copyWith(color: AppColors.textSecondary), // [DU279 PS10] tiny grey400 1.88
                      ),
                    ],
                    if (work.taxDeductionType != InsuranceRateModel.typeNone) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: ResponsiveHelper.iconSize(context, 14), color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            InsuranceRateModel.typeLabel(
                                work.taxDeductionType),
                            style: ResponsiveHelper.smallStyle(context)
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ],

                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                    // ── 모집 인원 ────────────────────────────
                    _buildInfoBlock(
                        context, '모집 인원', '${work.requiredCount}명'),

                    // ── 근무 조건 섹션 (있을 때만) ───────────
                    if (workType != null &&
                        (workType.duties != null ||
                            workType.workEnvironment != null ||
                            workType.requirements != null ||
                            workType.precautions != null)) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                      const Divider(height: 1, color: AppColors.grey200),
                      SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                      // 주요 업무 — 핵심 정보, 앞에 배치
                      if (workType.duties != null) ...[
                        _buildInfoBlock(
                            context, '주요 업무', workType.duties!),
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      ],

                      // 근무 환경
                      if (workType.workEnvironment != null) ...[
                        _buildInfoBlock(
                            context, '근무 환경', workType.workEnvironment!),
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      ],

                      // 지원 조건
                      if (workType.requirements != null) ...[
                        _buildInfoBlock(
                            context, '지원 조건', workType.requirements!),
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      ],

                      // 유의사항 — warning card 유지
                      if (workType.precautions != null)
                        CommonWidgets.infoCard(
                          context: context,
                          message: workType.precautions!,
                          icon: Icons.warning_amber_outlined,
                          color: AppColors.warningDark,
                        ),
                    ],

                    SizedBox(height: ResponsiveHelper.spacing(context, 32)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkTypeImages(
      BuildContext context, BusinessWorkTypeModel workType) {
    final images = <String>[];
    if (workType.thumbnailUrl != null) images.add(workType.thumbnailUrl!);
    if (workType.images != null) images.addAll(workType.images!);
    if (images.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        itemBuilder: (_, i) => GestureDetector(
          // 탭 → 전체화면 뷰어 (찾아오는 길과 동일한 컴포넌트 재사용)
          // BoxFit.contain · 핀치줌 · 확대 후 드래그 · 좌우 스와이프 모두 지원
          onTap: () => CommonWidgets.showImagePreview(
            context, images, initialIndex: i),
          child: Container(
            width: 240,
            margin: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 12)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ImageHelper.buildCachedImage(images[i],
                  fit: BoxFit.cover, memCacheWidth: 720, memCacheHeight: 540),
            ),
          ),
        ),
      ),
    );
  }

  /// 정보 블록 — 작은 라벨(grey) + 본문 텍스트 계층 구조
  /// 폼 스타일의 회색 박스 없이 읽기 전용 정보 화면에 적합
  Widget _buildInfoBlock(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [DU279 PS9] 라벨 tiny grey400 w700 자간(1.88) → small 보조색 w600
        Text(
          label,
          style: ResponsiveHelper.smallStyle(context).copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 5)),
        // [DU279 PS14] 값은 낱말 단위(B320 '실근/무'). 읽기 이름은 원문.
        Text(
          TextLayout.keepWords(value),
          semanticsLabel: value,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            color: valueColor ?? AppColors.textPrimary,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ── Actions ───────────────────────────────────

  void _showFullMap(BuildContext context) {
    if (_business?.latitude == null || _business?.longitude == null) {
      ToastHelper.showError('위치 정보가 없습니다');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => FullMapDialog(business: _business!),
    );
  }

  Future<void> _callPhone(String phone) async {
    try {
      await launchUrl(Uri.parse('tel:$phone'));
    } catch (e) {
      if (mounted) ToastHelper.showError('전화를 걸 수 없습니다');
    }
  }

  /// 선택된 업무 확인 시트 표시 후 지원 실행
  Future<void> _showConfirmAndApply() async {
    if (_isLoading || _isApplying) return;
    if (_to == null) return;

    // 전제조건 확인
    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;
    // [PII-B4-R1.4 §39] 서버가 보는 세무 축을 클라이언트도 같이 본다.
    //   조회 실패는 막지 않는다 — 최종 판단은 callableApplyToTO가 한다.
    final applyTax = await _takeTaxStatus();
    if (!mounted) return;
    if (!meetsApplyPrerequisites(user,
        isFlexType: _to!.isFlexType, taxStatus: applyTax)) {
      final ok = await ApplyPrerequisitesScreen.show(context, isFlexType: _to!.isFlexType);
      if (!ok || !mounted) return;
    }

    // [POSTING-V2-03C.1] 근무일 목록이 불완전하면 지원을 진행하지 않는다.
    //   _allSlots가 비어 있어도 아래 폴백이 _currentWorkDetails로 items를
    //   채우므로, 잘린 데이터 위에서 지원이 성립할 수 있었다.
    //   공고 전체를 잠그지는 않고 slot 의존 action만 막는다.
    if (_to!.isFlexType && _slotLoadError) {
      ToastHelper.showError('근무 일정을 불러오지 못했습니다');
      return;
    }

    // 선택 목록 수집
    // [R7-P4.4E.7A] 카운트와 **같은 목록**을 쓴다. 세는 곳과 보내는 곳이
    //   갈라지면 `N개 업무 선택됨` 과 실제 제출이 어긋난다.
    final List<({SlotModel? slot, WorkDetailModel work})> items = [
      ..._newApplyTargets,
    ];

    if (items.isEmpty) {
      // 아무것도 선택 안 됐으면 전체 업무로 (멀티 날짜 선택 없이 전체 지원).
      //   여기서도 이미 관계가 있는 근무는 넣지 않는다.
      if (_to!.isFlexType) {
        if (_currentWorkDetails.isNotEmpty) {
          for (final wd in _currentWorkDetails.where((w) => !w.isTimeExpired)) {
            if (_relationFor(wd, _currentSlot).blocksNewApplication) continue;
            items.add((slot: _currentSlot, work: wd));
          }
        }
      } else if (_contractSelected.isEmpty) {
        for (final work in _workDetails) {
          if (_relationFor(work, null).blocksNewApplication) continue;
          items.add((slot: null, work: work));
        }
      }
    }

    if (items.isEmpty) {
      if (mounted) ToastHelper.showError('지원할 업무가 없습니다');
      return;
    }

    if (!mounted) return;
    setState(() => _isApplying = true);
    try {
      // 장기 TO: LongTermApplySheet (변경 없음)
      if (_to!.isLongTerm) {
        final works = items.map((i) => i.work).toList();
        if (!mounted) return;
        final result = await LongTermApplySheet.show(
          context: context,
          to: _to!,
          selectedWorks: works,
          businessName: _to!.businessName,
          myApplications: _myApplications,
          // [R7-PAYROLL-POLICY.4C] 이 화면이 `[상세 기준]` 으로 보여준 그 값.
          //   새로 읽지 않는다 — 보여준 것과 보내는 것이 같아야 한다.
          policyRules: _business?.attendanceRules,
        );
        // 기준이 바뀌어 막혔으면 **닫지 않고** 이 화면을 다시 읽는다. 그러면
        //   `[상세 기준]` 이 최신 값을 보여주고, 근로자가 확인한 뒤 다시
        //   지원할 수 있다(자동 재지원 없음).
        if (result?.policyChanged == true && mounted) {
          await _refreshAfterPolicyChange();
          return;
        }
        if (result?.hasChanges == true && mounted) Navigator.pop(context, true);
        return;
      }

      // 단기 TO (flex + contract): Multi Apply Confirm 1회
      // [JPS-REFACTOR] AWD 제거 — BottomSheet depth: 3 → 1
      // 이전: _buildConfirmSheetContent → AWD → ApplyConfirmDialog × N
      // 이후: MultiApplyConfirmSheet (conflict check + consent + CF × N + result)
      // [NOTE] UserTOCard 경로는 ApplyWorkDialog → ApplyConfirmDialog 유지
      final result = await DialogHelper.showSheet<MultiApplyResult>(
        context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (ctx) => MultiApplyConfirmSheet(
          items: items,
          to: _to!,
          myApplications: _myApplications,
          // [R7-PAYROLL-POLICY.4C] 이 화면이 보여준 그 값(새 읽기 없음).
          policyRules: _business?.attendanceRules,
        ),
      );
      if (result?.policyChanged == true && mounted) {
        await _refreshAfterPolicyChange();
        return;
      }
      if (result?.hasChanges == true && mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }


  // ═══════════════════════════════════════════════════════════════════════════
  // 내 지원 상태 카드 (내 지원에서 진입 시)
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildMyApplicationSection(BuildContext context) {
    final app = widget.myApplication!;
    final contract = widget.myContract;
    final s = ResponsiveHelper.spacing(context, 16);

    // ── 상태별 표시 정보 결정 ──────────────────────────────────────────────
    final String badgeLabel;
    final Color badgeColor;
    final Color badgeBgColor;
    final String mainMessage;
    String? subMessage;
    bool showDateRow = false;
    bool showCancelAction = false;
    bool showContractAction = false;
    bool showInviteActions = false;

    switch (app.status) {
      case AppStatus.pending:
        badgeLabel  = '대기 중';
        badgeColor  = AppColors.warningDark;
        badgeBgColor = AppColors.warningBg;
        mainMessage = '관리자가 지원 내용을 확인하고 있어요.\n확정되면 알려드릴게요.';
        showCancelAction = true;

      case AppStatus.contractPending:
        if (contract == null) {
          badgeLabel  = '계약 진행 중';
          badgeColor  = AppColors.infoDark;
          badgeBgColor = AppColors.infoBg;
          mainMessage = '채용이 결정되었어요.\n관리자가 계약서를 준비하고 있습니다.';
        } else {
          switch (contract.status) {
            case ContractStatus.pendingWorker:
              badgeLabel  = '서명 필요';
              badgeColor  = AppColors.brand;
              badgeBgColor = AppColors.infoBg;
              mainMessage = '계약서가 도착했어요.\n내용을 확인하고 서명해주세요.';
              showContractAction = true;
            case ContractStatus.pendingEmployer:
              badgeLabel  = '계약 진행 중';
              badgeColor  = AppColors.infoDark;
              badgeBgColor = AppColors.infoBg;
              mainMessage = '계약서 작성이 완료되었어요.\n관리자 서명을 기다리고 있습니다.';
            default:
              badgeLabel  = '계약 완료';
              badgeColor  = AppColors.successDark;
              badgeBgColor = AppColors.successBg;
              mainMessage = '계약이 완료되었어요.';
          }
        }

      case AppStatus.confirmed:
        badgeLabel  = '확정';
        badgeColor  = AppColors.successDark;
        badgeBgColor = AppColors.successBg;
        mainMessage = '근무가 확정되었습니다.';
        showDateRow = true;

      case AppStatus.rejected:
        badgeLabel  = '지원 종료';
        // [DU466e · 후속116b N116-3] 빨강 → 다른 종료 상태(취소 · 자동취소 · 만료)와 같은 중립 짝. 빨강은 확인 순간에만.
        badgeColor  = AppColors.textSecondary;
        badgeBgColor = AppColors.grey100;
        mainMessage = '이번 지원은 확정되지 않았어요.';
        if (app.rejectMessage?.isNotEmpty == true) {
          subMessage = app.rejectMessage;
        }

      case AppStatus.canceled:
        badgeLabel  = '취소';
        // [DU466] 중립 칩 grey600/grey100(4.22) → textSecondary/grey100(중립 상태 칩 짝 · DU274 · 소급8).
        badgeColor  = AppColors.textSecondary;
        badgeBgColor = AppColors.grey100;
        mainMessage = _cancelDetailText(app.cancelReason);

      case AppStatus.autoCanceled:
        // [CROSS-DOMAIN-R5.3D.1] 제안을 받아들여 접힌 지원은 취소가 아니다.
        //   판정은 cancelReason 하나로 한다(ApplicationModel.isReassignedAway).
        if (app.isReassignedAway) {
          badgeLabel  = '다른 업무로 확정됨';
          badgeColor  = AppColors.successDark;
          badgeBgColor = AppColors.successBg;
        } else {
          badgeLabel  = '자동 취소';
          // [DU466] grey600/grey100(4.22) → textSecondary/grey100.
          badgeColor  = AppColors.textSecondary;
          badgeBgColor = AppColors.grey100;
        }
        mainMessage = _autoCancelDetailText(app.cancelReason);

      case AppStatus.invited:
        badgeLabel  = '근무 초대';
        badgeColor  = AppColors.infoDark;
        badgeBgColor = AppColors.infoBg;
        mainMessage = '새로운 근무 초대가 도착했어요.';
        showInviteActions = true;

      case AppStatus.expired:
        badgeLabel  = '초대 종료';
        // [DU466] grey600/grey200(3.97) → textSecondary/grey100(같은 중립 칩 짝).
        badgeColor  = AppColors.textSecondary;
        badgeBgColor = AppColors.grey100;
        mainMessage = '응답 기간이 지나 초대가 종료되었어요.';

      default:
        return const SizedBox.shrink();
    }

    // ── 날짜/시간 행 (CONFIRMED) ───────────────────────────────────────────
    Widget? dateRowWidget;
    if (showDateRow) {
      final days = ['월', '화', '수', '목', '금', '토', '일'];
      String dateStr;
      if (app.isLongTermApplication) {
        final start = app.desiredStartDate ?? app.workDate;
        final end   = app.actualResignDate ?? app.workEndDate;
        final startS = FormatHelper.formatDateCompact(start);
        dateStr = end != null
            ? '$startS ~ ${FormatHelper.formatDateCompact(end)}'
            : startS;
      } else {
        final dt = app.workDate;
        dateStr = '${dt.month}월 ${dt.day}일(${days[dt.weekday - 1]})';
        if (app.startTime.isNotEmpty && app.endTime.isNotEmpty) {
          dateStr += ' · ${app.startTime}~${app.endTime}';
        }
      }
      dateRowWidget = Row(
        children: [
          const Icon(Icons.calendar_today_outlined,
              size: 13, color: AppColors.grey500),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              dateStr,
              style: ResponsiveHelper.smallStyle(context)
                  .copyWith(color: AppColors.grey700),
            ),
          ),
        ],
      );
    }

    // ── 레이아웃 ─────────────────────────────────────────────────────────────
    return Container(
      margin: EdgeInsets.only(top: s / 2),
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(s, s, s, s + 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 라벨 "내 지원"
          Text(
            '내 지원',
            // [DU466] 구역 이름표 grey400(1.88) → textSecondary.
            style: ResponsiveHelper.tinyStyle(context).copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),

          // 배지 + 메인 메시지
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeBgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: badgeColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                // [DU466e] B 에서 '확 / 정되지' 처럼 낱말 안에서 끊겼다 — 낱말 사이에서만 줄바꿈(읽기는 원문).
                child: Text(
                  TextLayout.keepWords(mainMessage),
                  semanticsLabel: mainMessage,
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),

          // 거절 메시지 (있을 때만)
          if (subMessage != null && subMessage.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              // [DU466e] 거절 사유도 낱말 단위('맞지 않 / 아' 끊김).
              TextLayout.keepWords(subMessage),
              semanticsLabel: subMessage,
              style: ResponsiveHelper.tinyStyle(context)
                  // [DU466] 거절 안내 grey500(2.68) → textTertiary(보조 줄).
                  .copyWith(color: AppColors.textTertiary, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // 날짜/시간 (CONFIRMED)
          if (dateRowWidget != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            dateRowWidget,
          ],

          // 계약서 확인 버튼 (CONTRACT_PENDING + pendingWorker)
          if (showContractAction) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 14)),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isContractSignOpening
                    ? null : _openContractSignFromDetail,
                icon: const Icon(Icons.draw_outlined, size: 16),
                label: Text(
                  _isContractSignOpening ? '열고 있습니다...' : '계약서 확인하기',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.grey200,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 12)),
                  textStyle: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],

          // 초대 수락/거절 버튼 (INVITED)
          if (showInviteActions) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_isAcceptingInvite || _isDecliningInvite)
                        ? null : _acceptInviteFromDetail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 10)),
                      textStyle: ResponsiveHelper.bodyStyle(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    child: Text(_isAcceptingInvite ? '처리 중...'
                        // [R5.3B.1] 제안은 초대가 아니다 — 기존 지원을 대신한다.
                        : (widget.myApplication?.isAlternativeWorkOffer ?? false)
                            ? '제안 수락' : '초대 수락'),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: OutlinedButton(
                    onPressed: (_isAcceptingInvite || _isDecliningInvite)
                        ? null : _declineInviteFromDetail,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.grey600,
                      side: const BorderSide(color: AppColors.grey300),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 10)),
                      textStyle: ResponsiveHelper.bodyStyle(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    child: Text(_isDecliningInvite ? '처리 중' : '거절'),
                  ),
                ),
              ],
            ),
          ],

          // 지원 취소 링크 (PENDING)
          if (showCancelAction) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            GestureDetector(
              onTap: _isCancellingApplication ? null : _cancelApplicationFromDetail,
              child: Text(
                _isCancellingApplication ? '취소 처리 중...' : '지원 취소하기',
                style: TextStyle(
                  fontSize: 12,
                  color: _isCancellingApplication
                      ? AppColors.grey400 : AppColors.errorDark,
                  decoration: TextDecoration.underline,
                  decorationColor: _isCancellingApplication
                      ? AppColors.grey400 : AppColors.errorDark,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 내 지원 진입 시 하단 바 ──────────────────────────────────────────────────

  Widget _buildApplicationBottomBar(BuildContext context) {
    final app = widget.myApplication!;
    final contract = widget.myContract;

    // CONTRACT_PENDING + 근로자 서명 필요 → "계약서 확인하기" sticky CTA
    if (app.status == AppStatus.contractPending &&
        contract?.status == ContractStatus.pendingWorker) {
      return SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isContractSignOpening
                  ? null : _openContractSignFromDetail,
              icon: const Icon(Icons.draw_outlined, size: 18),
              label: Text(
                _isContractSignOpening ? '열고 있습니다...' : '계약서 확인하기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.grey200,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 14)),
                textStyle: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      );
    }

    // INVITED → "초대 수락" / "거절" sticky 버튼
    if (app.status == AppStatus.invited) {
      return SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                // [CROSS-DOMAIN-R5.3D] 정보 접근과 수락 가능 여부를 분리한다.
                //   FULL/CLOSED/UNKNOWN이어도 초대 조건은 위에 그대로 보이고,
                //   여기 버튼만 잠긴다. 이유는 promise 카드가 말한다.
                child: ElevatedButton(
                  onPressed: (_isAcceptingInvite || _isDecliningInvite ||
                          !(_invitationProjection(postingLoaded: _to != null)
                                  ?.canAccept ??
                              true))
                      ? null : _acceptInviteFromDetail,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 14)),
                    textStyle: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  child: Text(_isAcceptingInvite ? '처리 중...'
                        // [R5.3B.1] 제안은 초대가 아니다 — 기존 지원을 대신한다.
                        : (widget.myApplication?.isAlternativeWorkOffer ?? false)
                            ? '제안 수락' : '초대 수락'),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: OutlinedButton(
                  onPressed: (_isAcceptingInvite || _isDecliningInvite)
                      ? null : _declineInviteFromDetail,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.grey600,
                    side: const BorderSide(color: AppColors.grey300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(context, 14)),
                    textStyle: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  child: Text(_isDecliningInvite ? '처리 중...' : '거절'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // CONFIRMED / PENDING / REJECTED / CANCELED / EXPIRED → 하단 CTA 없음
    return const SizedBox.shrink();
  }

  // ── cancelReason 사용자 메시지 ────────────────────────────────────────────

  String _cancelDetailText(String? reason) {
    switch (reason) {
      case 'USER_CANCELED':   return '직접 취소한 지원이에요.';
      case 'SAME_DAY_CANCEL': return '당일 취소 처리된 지원이에요.';
      case 'ADMIN_CANCELED':  return '사업장 사정으로 근무가 취소되었어요.';
      default:                return '취소된 지원이에요.';
    }
  }

  String _autoCancelDetailText(String? reason) {
    switch (reason) {
      case 'SCHEDULE_CONFLICT':
        return '다른 근무가 확정되어\n시간이 겹치는 지원이 자동으로 취소되었어요.';
      case 'WORK_DETAIL_EXPIRED':
      case 'SLOT_WORK_DETAIL_EXPIRED':
      case 'TO_EXPIRED':
        return '모집이 마감되어 지원이 자동으로 취소되었어요.';
      case 'TO_DELETED':
        return '공고가 삭제되어 지원이 자동으로 취소되었어요.';
      // [R5.3D.1] 제안 수락의 결과 — 이력은 남지만 취소가 아니다.
      case 'REASSIGNMENT_ACCEPTED':
        return '제안받은 다른 업무로 확정되어\n이 지원은 정리되었어요.\n'
            '취소·노쇼 불이익은 적용되지 않습니다.';
      default:
        return '지원이 자동으로 취소되었어요.';
    }
  }

  // ── 내 지원 액션 핸들러 ───────────────────────────────────────────────────

  Future<void> _cancelApplicationFromDetail() async {
    if (_isCancellingApplication) return;
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) { ToastHelper.showError('로그인이 필요합니다.'); return; }

    final confirmed = await DialogHelper.showCancelConfirm(
      context,
      title: '지원 취소',
      message: '지원을 취소하시겠습니까?',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isCancellingApplication = true);
    try {
      final success = await _firestoreService.cancelApplication(
          widget.myApplication!.id, uid);
      if (mounted && success) {
        ToastHelper.showSuccess('지원이 취소되었습니다.');
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('❌ 지원 취소 오류: $e');
      if (mounted) ToastHelper.showError('취소 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _isCancellingApplication = false);
    }
  }

  Future<void> _openContractSignFromDetail() async {
    if (_isContractSignOpening || widget.myContract == null) return;
    setState(() => _isContractSignOpening = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContractSignScreen(
            contract: widget.myContract!,
            role: 'worker',
          ),
        ),
      );
      // 서명 여부와 무관하게 목록으로 돌아가 상태 새로고침
      if (mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _isContractSignOpening = false);
    }
  }

  Future<void> _acceptInviteFromDetail() async {
    if (_isAcceptingInvite) return;
    final app = widget.myApplication!;

    // [CROSS-DOMAIN-R5.3B.1] 이 화면의 수락은 R5.2 이후 **항상 실패**하고 있었다.
    //
    //   R5.2가 수락을 직접 지원과 같은 문턱에 올리면서(서류 준비 + 이 건에
    //   대한 동의) 내 지원내역 화면만 고쳤다. 공고 상세의 수락 버튼은
    //   applicationId만 보내 서버가 invalid-argument로 되돌려보냈다.
    //   DEV 실측: 400 "소득신고·급여처리 목적 서류 접근에 동의해야…"
    //
    //   같은 commitment를 만드는 버튼이므로 같은 조건을 쓴다.
    final isOffer = app.isAlternativeWorkOffer;
    final user = context.read<UserProvider>().currentUser;
    if (user == null) { ToastHelper.showError('로그인이 필요합니다.'); return; }
    final isFlex = _to?.isFlexType ?? true;
    final acceptTax = await TaxIdentityService.loadStatus();
    if (!mounted) return;
    if (!meetsApplyPrerequisites(user,
        isFlexType: isFlex, taxStatus: acceptTax)) {
      ToastHelper.showWarning('근무 확정을 위해 서류 등록이 필요합니다.');
      final ok = await ApplyPrerequisitesScreen.show(context, isFlexType: isFlex);
      if (!ok || !mounted) return;
    }

    final confirmed = await DialogHelper.showCustom<bool>(
      context,
      title: isOffer ? '다른 업무 제안 수락' : '초대 수락',
      icon: isOffer ? Icons.swap_horiz : Icons.check_circle_outline,
      iconColor: AppColors.success,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isOffer
                // 제안은 초대와 결과가 다르다 — 기존 지원이 접힌다는 것을 먼저 말한다.
                ? '제안받은 업무로 확정되고, 기존 지원'
                    '${app.sourceWorkType != null ? "(${app.sourceWorkType})" : ""}'
                    // [R5.3D.1] 이력은 남는다 — 사라지는 것은 불이익이다.
                    "은 '다른 업무로 확정됨'으로 정리됩니다.\n"
                    '취소·노쇼 불이익은 적용되지 않습니다.'
                : '이 업무에 참여하시겠습니까?\n수락 후 일정 충돌이 없으면 확정됩니다.',
          ),
          const SizedBox(height: 12),
          DocumentAccessConsent.inviteCard(app.businessName),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('취소'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
          child: Text(isOffer ? '동의하고 제안 수락' : '동의하고 초대 수락',
              style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isAcceptingInvite = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableAcceptTOInvitation');
      // 내 지원내역 경로와 **같은** payload — 두 곳이 다른 것을 보내면 안 된다.
      await callable.call({
        'applicationId': app.id,
        'documentAccessConsentGiven': true,
        'documentAccessConsentVersion': DocumentAccessConsent.inviteVersion,
      });
      if (!mounted) return;
      ToastHelper.showSuccess('초대를 수락했습니다!');
      Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ToastHelper.showError(e.message ?? '수락 중 오류가 발생했습니다.');
    } catch (e) {
      if (mounted) ToastHelper.showError('수락 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _isAcceptingInvite = false);
    }
  }

  Future<void> _declineInviteFromDetail() async {
    if (_isDecliningInvite) return;
    final confirmed = await DialogHelper.showDeclineInviteConfirm(context);
    if (!confirmed || !mounted) return;

    setState(() => _isDecliningInvite = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableDeclineTOInvitation');
      // [INVITE-DECLINE-INTENT] 상태를 보여 준 뒤의 명시 거절임을 서버에 알린다.
      await callable.call({
        'applicationId': widget.myApplication!.id,
        'declineIntent': 'EXPLICIT',
      });
      if (!mounted) return;
      ToastHelper.showInfo('초대를 거절했습니다.');
      Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ToastHelper.showError(e.message ?? '거절 중 오류가 발생했습니다.');
    } catch (e) {
      if (mounted) ToastHelper.showError('거절 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _isDecliningInvite = false);
    }
  }

}

/// [DU1 구현114 S041 접힌 사진 숨은 탭] 사업장 사진 갤러리(SliverAppBar flexibleSpace 배경)가 **완전히 접혀 보이지 않을 때만**
///   사진이 포인터를 받지 않게 한다. SliverAppBar 가 이미 내려주는 [FlexibleSpaceBarSettings](current/minExtent)를 읽을 뿐이며
///   새 listener·스크롤 owner 를 두지 않는다. child 는 부모가 만든 그대로 넘겨 스크롤 프레임마다 갤러리를 다시 만들지 않는다.
///   이유: SDK FlexibleSpaceBar(pin)는 접힌 뒤에도 배경을 툴바 아래(390×844 실측 top −184)에 남기고, 불투명도 0 에서도 hit 를 자식에게
///   넘긴다 — 보이지 않는 사진이 툴바 탭을 받아 미리보기를 열었다(구현113·114 실측). 중간 접힘에서는 배경이 보이므로(불투명도 > 0) 기존과 같다.
class _GalleryHiddenInputGate extends StatelessWidget {
  const _GalleryHiddenInputGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bar = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final hidden = bar != null && bar.currentExtent <= bar.minExtent;
    // [DU1 구현118] 보이지 않는 사진은 의미 노드로도 내놓지 않는다 — 이름을 단 사진 노드가 완전 접힘에서 동작 없이 읽히지 않게(구현118 후보A 실측).
    return IgnorePointer(ignoring: hidden, child: ExcludeSemantics(excluding: hidden, child: child));
  }
}
