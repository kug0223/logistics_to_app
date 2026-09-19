import 'dart:math' show max;

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

// Models (slot, application)
import '../../models/core/slot_model.dart';
import '../../models/core/application_model.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/image_helper.dart';
import '../../utils/dialog_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/loading_widget.dart';
// WorkTypeIcon import removed — 업무카드 placeholder 아이콘 제거 (spec 요구)
import '../../widgets/maps/kakao_map_widget.dart';
import '../../widgets/maps/full_map_dialog.dart';
import '../../widgets/dialogs/apply/multi_apply_confirm_sheet.dart';
import '../../widgets/dialogs/apply/longterm_apply_sheet.dart';
import '../../widgets/dialogs/apply/apply_summary_section.dart';
import '../../widgets/dialogs/apply/document_access_consent.dart';
import '../../theme/app_colors.dart';
import '../user/apply_prerequisites_screen.dart';
import 'document_management_screen.dart';
// ── 내 지원 진입 전용 ─────────────────────────────────────────────────────────
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/core/employment_contract_model.dart';
import '../contract/contract_sign_screen.dart';
// [CROSS-DOMAIN-R5.3D] 통합 초대 상세 — promise / context / acceptability 분리
import '../../models/ui/invitation_projection.dart';
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
  UserProvider? _userProvider;

  bool _isLoading = true;
  TOModel? _to;
  BusinessModel? _business;
  List<WorkDetailModel> _workDetails = [];
  Map<String, BusinessWorkTypeModel> _workTypeMap = {};

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

  int get _totalSelectedCount {
    if (_to?.isFlexType ?? false) return _flexSelected.length;
    return _contractSelected.length;
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

  void _toggleWork(WorkDetailModel work) {
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
    } else if (!user.isPassVerified) {
      newReason = '본인인증이 필요합니다';
    } else if (!user.hasIdDocument) {
      newReason = '신분증 등록이 필요합니다';
    } else if (_to?.jobType == TOType.flex && !user.isIdVerified) {
      newReason = '신분증 인증이 필요합니다';
    }
    // [PII-DOC-R1.5.2] 계좌·통장사본 차단 사유를 여기서 뺐다.
    //   서버가 더 이상 요구하지 않으므로 앱이 먼저 막으면 화면과 서버가
    //   다른 말을 하게 된다. meetsApplyPrerequisites도 같이 정리했다.
    if (newReason != _applyBlockReason) {
      setState(() => _applyBlockReason = newReason);
    }
  }

  /// 서류 미완료로 인한 차단 여부 — 신분증 관련 사유만 해당
  /// 블랙리스트·페널티·본인인증 차단과 구분하여 바텀시트로 안내
  // [PII-DOC-R1.5.2] '통장' 매칭 제거 — 통장은 더 이상 차단 사유가 아니다.
  bool get _isDocumentBlocked {
    final r = _applyBlockReason;
    if (r == null) return false;
    return r.contains('신분증');
  }

  bool get _isEffectivelyClosed {
    if (_to == null) return false;
    if (_to!.isClosed) return true;
    final req = _slot?.workDetails.fold<int>(0, (s, wd) => s + wd.requiredCount)
        ?? widget.slotTotalRequired
        ?? _to!.totalRequired;
    final conf = _slot?.confirmedCount ?? widget.slotConfirmedCount ?? _to!.totalConfirmed;
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

  Future<void> _loadData() async {
    _applicantUid = widget.mode == TODetailMode.applicant
        ? context.read<UserProvider>().currentUser?.uid
        : null;
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
        final loaded = await _firestoreService.getTOOrFailure(widget.toId!);
        _to = loaded.to;
        _loadFailed = loaded.failed;
        if (_to != null) {
          final results = await Future.wait([
            _firestoreService.getWorkDetails(_to!.id),
            _firestoreService.getBusinessById(_to!.businessId),
          ]);
          _workDetails = results[0] as List<WorkDetailModel>;
          _business = results[1] as BusinessModel?;
        }
      }
      if (_business == null && _to != null) {
        await Future.wait([
          _firestoreService.getBusinessById(_to!.businessId)
              .then((biz) { _business = biz; }),
          if (_to!.isFlexType) _loadSlots(),
          if (widget.mode == TODetailMode.applicant && _applicantUid != null)
            _firestoreService.getMyApplications(_applicantUid!)
                .then((apps) { _myApplications = apps; }),
        ]);
        if (_business != null) await _loadWorkTypes();
      } else {
        await Future.wait([
          if (_to != null && _to!.isFlexType) _loadSlots(),
          if (_business != null) _loadWorkTypes(),
          if (widget.mode == TODetailMode.applicant && _applicantUid != null)
            _firestoreService.getMyApplications(_applicantUid!)
                .then((apps) { _myApplications = apps; }),
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
      final slots = await _firestoreService.getSlots(_to!.id, visibleOnly: false);
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
        final sd = widget.slotDate!;
        _slot = slots.where((s) =>
            s.date.year == sd.year &&
            s.date.month == sd.month &&
            s.date.day == sd.day).firstOrNull;
        if (_workDetails.isEmpty && _slot != null) {
          _workDetails = _slot!.workDetails;
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
      final workTypes = await _firestoreService.getBusinessWorkTypes(_business!.id);
      _workTypeMap = {for (var wt in workTypes) wt.name: wt};
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
      final one = await _firestoreService.getApplicationOnce(srcId);
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
      backgroundColor: AppColors.grey50,
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
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 16),
                              vertical: ResponsiveHelper.spacing(context, 4),
                            ),
                            child: ApplySummarySection(
                              myApplications: _myApplications,
                              currentToId: _to?.id,
                            ),
                          ),
                          if (_business?.precautions != null &&
                              _business!.precautions!.isNotEmpty)
                            _buildPrecautionsSection(context),
                          if (_business != null) _buildFacilitiesSection(context),
                          if (_business != null) _buildTransportSection(context),
                          SizedBox(height: ResponsiveHelper.spacing(context, 100)),
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
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
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
      backgroundColor: Colors.black87,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
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
            PageView.builder(
              controller: _galleryController,
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _galleryPage = i),
              itemBuilder: (_, i) => GestureDetector(
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

  Widget _buildPostingHeader(BuildContext context) {
    final s = ResponsiveHelper.spacing(context, 16);

    final isEffectivelyClosed = _isEffectivelyClosed;
    final isSoonDeadline = !isEffectivelyClosed && _isAnySoonDeadline();

    final (statusLabel, statusColor) = isEffectivelyClosed
        ? ('모집 종료', AppColors.grey500)
        : isSoonDeadline
            ? ('마감임박', AppColors.warning)
            : ('모집중', AppColors.success);

    return Container(
      color: Colors.white,
      padding: EdgeInsets.all(s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 사업장 영역 ────────────────────────────
          if (_business != null) ...[
            // 사업장명 (공고 제목보다 크게, 명확하게)
            Text(
              _business!.name,
              style: ResponsiveHelper.titleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold, height: 1.3),
            ),
            // 핵심 시설/환경 배지 칩
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildFacilityBadgeChips(context),
            // 한줄 소개
            if (_business!.oneLineIntro != null &&
                _business!.oneLineIntro!.isNotEmpty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
              Text(
                _business!.oneLineIntro!,
                style: ResponsiveHelper.smallStyle(context)
                    .copyWith(color: AppColors.grey600, height: 1.4),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // 사업장/공고 구분선
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            const Divider(height: 1, color: AppColors.grey100),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ],

          // ── 공고 영역 ──────────────────────────────
          // 공고 제목 + 상태 배지 (사업장명보다 작은 위계)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _to!.title,
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold, height: 1.3),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          // 근무유형 칩 (단기 · 익일지급 · 장기가능)
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _buildWorkTypeBadgeChips(context),
          // 공고 설명
          if (_to!.description != null && _to!.description!.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              _to!.description!,
              style: ResponsiveHelper.smallStyle(context)
                  .copyWith(color: AppColors.grey600, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
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
  Widget _buildWorkTypeBadgeChips(BuildContext context) {
    final chips = <({String label, Color color})>[];

    // 근무 유형
    chips.add((label: _to!.jobTypeLabel, color: _to!.isLongTerm ? AppColors.purple : AppColors.info));

    // 대표 급여 지급 방식 (첫 번째 workDetail 기준)
    if (_workDetails.isNotEmpty) {
      final payLabel = _workDetails.first.payScheduleTypeLabel;
      if (payLabel.isNotEmpty) {
        chips.add((label: payLabel, color: AppColors.successMedium));
      }
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: chips.map((c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          c.label,
          style: ResponsiveHelper.tinyStyle(context).copyWith(
            color: c.color,
            fontWeight: FontWeight.w600,
          ),
        ),
      )).toList(),
    );
  }

  // ── 3. 날짜 선택 (flex TO) ────────────────────

  /// 단기 공고인데 유효한 슬롯이 없을 때 — 날짜 선택기 대신 안내 메시지
  /// (슬롯 미생성 / 마감 초과 / visibleFrom 미도달 공통 처리)
  Widget _buildNoSlotsMessage(BuildContext context) {
    return Container(
      color: Colors.white,
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 20),
      ),
      child: Row(
        children: [
          Icon(Icons.event_busy_outlined,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.grey400),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Text(
            '현재 선택 가능한 근무 날짜가 없습니다.',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
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
    return Container(
      color: Colors.white,
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 20),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.grey400),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Text(
              '근무 일정을 불러오지 못했습니다.\n잠시 후 다시 시도해주세요.',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker(BuildContext context) {
    final s = ResponsiveHelper.spacing(context, 16);
    return Container(
      color: Colors.white,
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.only(top: s, bottom: s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '근무할 날짜를 선택하세요',
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                Text(
                  '어떤 날짜에 지원할 수 있어요',
                  style: ResponsiveHelper.smallStyle(context)
                      .copyWith(color: AppColors.grey500),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          SizedBox(
            height: 82,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: s),
              itemCount: _allSlots.length,
              itemBuilder: (_, i) => _buildDateChip(context, _allSlots[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateChip(BuildContext context, SlotModel slot) {
    final theme = Theme.of(context);
    final date = slot.date;
    final isSelected = _selectedSlotDate != null &&
        date.year == _selectedSlotDate!.year &&
        date.month == _selectedSlotDate!.month &&
        date.day == _selectedSlotDate!.day;

    final weekDays = ['월', '화', '수', '목', '금', '토', '일'];
    final dayLabel = weekDays[date.weekday - 1];
    final isWeekend = date.weekday >= 6;

    // 가능한 업무 수
    final availableCount = slot.workDetails
        .where((wd) => !wd.isTimeExpired)
        .length;
    final isClosed = slot.isEffectivelyClosed || availableCount == 0;

    return GestureDetector(
      onTap: isClosed ? null : () {
        setState(() => _selectedSlotDate = date);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 62,
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
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.85)
                    : isWeekend
                        ? AppColors.error.withValues(alpha: isClosed ? 0.4 : 1.0)
                        : AppColors.grey500,
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
                    : isWeekend
                        ? AppColors.error.withValues(alpha: isClosed ? 0.4 : 1.0)
                        : isClosed
                            ? AppColors.grey400
                            : AppColors.textPrimary,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 3)),
            Text(
              isClosed ? '마감' : '업무 $availableCount개',
              style: ResponsiveHelper.tinyStyle(context).copyWith(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.8)
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
    );
  }

  // ── 4. 업무 목록 ──────────────────────────────

  Widget _buildWorkSection(BuildContext context) {
    final s = ResponsiveHelper.spacing(context, 16);
    final workDetails = _currentWorkDetails;
    final currentSlot = _currentSlot;

    final slotReq = currentSlot?.workDetails.fold<int>(0, (a, wd) => a + wd.requiredCount)
        ?? widget.slotTotalRequired ?? _to!.totalRequired;
    final slotConf = currentSlot?.confirmedCount
        ?? widget.slotConfirmedCount ?? _to!.totalConfirmed;
    final isOverallClosed = _to!.isClosed || (slotReq > 0 && slotConf >= slotReq);

    // 날짜 헤더 텍스트
    String sectionTitle = '업무 목록';
    if (_selectedSlotDate != null && _to!.isFlexType) {
      final weekDays = ['월', '화', '수', '목', '금', '토', '일'];
      final d = _selectedSlotDate!;
      final dayStr = weekDays[d.weekday - 1];
      final available = workDetails.where((wd) => !wd.isTimeExpired).length;
      sectionTitle = '${d.month}월 ${d.day}일($dayStr) · 가능한 업무 $available개';
    }

    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      color: Colors.white,
      padding: EdgeInsets.all(s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.work_outline,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: Theme.of(context).primaryColor),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Expanded(
                child: Text(
                  sectionTitle,
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
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

  // ── 업무 카드 ─────────────────────────────────

  Widget _buildWorkCard(
    BuildContext context, {
    required WorkDetailModel work,
    required SlotModel? slot,
    required bool isOverallClosed,
  }) {
    final theme = Theme.of(context);
    final workType = _workTypeMap[work.workType];

    final workStats = widget.workDetailStats?[work.id];
    final workConfirmed = workStats?['confirmed'] ?? 0;
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
    final workAvailable =
        (workRequired - workConfirmed).clamp(0, workRequired);
    final hasWorkStats = widget.workDetailStats != null;

    final isWorkFull = workConfirmed >= workRequired && workRequired > 0;
    final isTimeExpired = work.isTimeExpired;
    final isClosed = isOverallClosed || isWorkFull || isTimeExpired;

    final now = DateTime.now();
    // 마감임박: 잔여 1명 이하 OR 업무 시작 2시간 이내
    final isAlmostFull = hasWorkStats && workAvailable == 1;
    bool isNearStart = false;
    if (slot != null) {
      try {
        final parts = work.startTime.split(':');
        final startDt = DateTime(
          slot.date.year, slot.date.month, slot.date.day,
          int.parse(parts[0]), int.parse(parts[1]),
        );
        final diffMins = startDt.difference(now).inMinutes;
        isNearStart = diffMins >= 0 && diffMins <= 120;
      } catch (_) {}
    }
    final isDeadlineSoon = !isClosed && (isAlmostFull || isNearStart);

    final (badgeLabel, badgeColor) = isClosed
        ? ('마감', AppColors.grey500)
        : isDeadlineSoon
            ? ('마감임박', AppColors.warning)
            : ('모집중', AppColors.success);

    // 이미지 유무로 레이아웃 분기 (16:9 대형 이미지 금지)
    final hasImage = workType?.thumbnailUrl != null;
    final isSelected = _isWorkSelected(work);
    final canSelect = widget.mode == TODetailMode.applicant && !isClosed;

    final availableColor = hasWorkStats
        ? (workAvailable > 1
            ? AppColors.info
            : workAvailable == 1
                ? AppColors.warning
                : AppColors.error)
        : AppColors.grey400;

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: isSelected
            ? theme.primaryColor.withValues(alpha: 0.03)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? theme.primaryColor : AppColors.grey200,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 메인 콘텐츠 행 ─────────────────────
          Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            child: Row(
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
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
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
                              style: ResponsiveHelper.subtitleStyle(context)
                                  .copyWith(
                                fontWeight: FontWeight.bold,
                                color: isClosed
                                    ? AppColors.grey500
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: badgeColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              badgeLabel,
                              style:
                                  ResponsiveHelper.tinyStyle(context).copyWith(
                                color: badgeColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // 한줄 업무 설명
                      if (workType?.description != null &&
                          workType!.description!.isNotEmpty) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                        Text(
                          workType.description!,
                          style: ResponsiveHelper.tinyStyle(context)
                              .copyWith(color: AppColors.grey500, height: 1.3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                      // 근무시간
                      Row(
                        children: [
                          Icon(Icons.access_time,
                              size: 13, color: AppColors.grey500),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Flexible(
                            child: Text(
                              '${work.startTime}~${work.endTime}'
                              '${_breakTimeStr(work).isNotEmpty ? ' ${_breakTimeStr(work)}' : ''}',
                              style: ResponsiveHelper.tinyStyle(context)
                                  .copyWith(color: AppColors.grey700),
                            ),
                          ),
                        ],
                      ),
                      if (_netTimeKorean(work).isNotEmpty) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 1)),
                        Padding(
                          padding: const EdgeInsets.only(left: 17),
                          child: Text(
                            '실근무 ${_netTimeKorean(work)}',
                            style: ResponsiveHelper.tinyStyle(context)
                                .copyWith(color: AppColors.grey400),
                          ),
                        ),
                      ],

                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),

                      // 급여
                      Row(
                        children: [
                          Icon(Icons.payments_outlined,
                              size: 13, color: AppColors.successMedium),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Flexible(
                            child: Text(
                              () {
                                final base =
                                    '${work.wageTypeLabel} ${work.formattedWage}';
                                final sched = work.payScheduleTypeLabel;
                                return sched.isNotEmpty ? '$base · $sched' : base;
                              }(),
                              style: ResponsiveHelper.tinyStyle(context)
                                  .copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.successDark,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // 세금 공제 — 낮은 우선순위 (보조 정보)
                      if (work.taxDeductionType != InsuranceRateModel.typeNone) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.receipt_long_outlined,
                                size: 11, color: AppColors.grey400),
                            const SizedBox(width: 3),
                            Text(
                              InsuranceRateModel.typeLabel(work.taxDeductionType),
                              style: ResponsiveHelper.tinyStyle(context)
                                  .copyWith(color: AppColors.grey400),
                            ),
                          ],
                        ),
                      ],

                      SizedBox(height: ResponsiveHelper.spacing(context, 6)),

                      // 모집인원 — 지원자 관점: 모집 n명 · 잔여 n명
                      RichText(
                        text: TextSpan(
                          style: ResponsiveHelper.tinyStyle(context)
                              .copyWith(color: AppColors.grey500),
                          children: [
                            const TextSpan(text: '모집 '),
                            TextSpan(
                              text: '$workRequired명',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.grey700),
                            ),
                            if (hasWorkStats) ...[
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
                                  fontWeight: FontWeight.bold,
                                  color: availableColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 구분선
          const Divider(height: 1, color: AppColors.grey100),

          // ── 버튼 행 ────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _showWorkTypeDetail(context, work, workType),
                    icon: const Icon(Icons.info_outline, size: 14),
                    label: const Text('업무 자세히 보기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.grey700,
                      side: const BorderSide(color: AppColors.grey300),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 8)),
                      textStyle: ResponsiveHelper.tinyStyle(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (canSelect) ...[
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: isSelected
                        ? ElevatedButton.icon(
                            onPressed: () => _toggleWork(work),
                            icon: const Icon(Icons.check_circle, size: 14),
                            label: const Text('선택됨'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(context, 8)),
                              textStyle: ResponsiveHelper.tinyStyle(context)
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: () => _toggleWork(work),
                            icon: const Icon(Icons.add_circle_outline, size: 14),
                            label: const Text('선택'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.primaryColor,
                              side: BorderSide(color: theme.primaryColor),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(context, 8)),
                              textStyle: ResponsiveHelper.tinyStyle(context)
                                  .copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 5. 준비사항 (칩 형태) ─────────────────────

  Widget _buildPrecautionsSection(BuildContext context) {
    final s = ResponsiveHelper.spacing(context, 16);
    final raw = _business!.precautions!;

    // 줄바꿈 기준으로 split → 칩 목록
    final items = raw
        .split(RegExp(r'[\n]'))
        .map((e) => e.trim().replaceAll(RegExp(r'^[·•\-\*]\s*'), ''))
        .where((e) => e.isNotEmpty)
        .toList();

    return Container(
      color: Colors.white,
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.all(s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.warning),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '준비사항',
                style: ResponsiveHelper.subtitleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 칩 목록 — 필수 항목(필수/필히/반드시/꼭) Orange, 일반 항목 Gray
          if (items.length <= 6)
            Wrap(
              spacing: ResponsiveHelper.spacing(context, 8),
              runSpacing: ResponsiveHelper.spacing(context, 8),
              children: items.map((item) {
                final isRequired = item.contains('필수') ||
                    item.contains('필히') ||
                    item.contains('반드시') ||
                    item.contains('꼭');
                return Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 6),
                  ),
                  decoration: BoxDecoration(
                    color: isRequired ? AppColors.warningBg : AppColors.grey100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isRequired
                          ? AppColors.warning.withValues(alpha: 0.5)
                          : AppColors.grey300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isRequired) ...[
                        const Icon(Icons.priority_high_rounded,
                            size: 12, color: AppColors.warningDark),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        item,
                        style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: isRequired
                              ? AppColors.warningDark
                              : AppColors.grey800,
                          fontWeight:
                              isRequired ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            )
          else
            // 항목이 많으면 텍스트로
            Text(
              raw,
              style: ResponsiveHelper.smallStyle(context)
                  .copyWith(color: AppColors.grey700, height: 1.6),
            ),
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
    final s = ResponsiveHelper.spacing(context, 16);

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
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.all(s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.business_center_outlined,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: theme.primaryColor),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text('시설 및 환경',
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Wrap(
            spacing: ResponsiveHelper.spacing(context, 8),
            runSpacing: ResponsiveHelper.spacing(context, 8),
            children: chips.map((c) => Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 10),
                vertical: ResponsiveHelper.spacing(context, 7),
              ),
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
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    c.label,
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      color: c.positive ? AppColors.grey800 : AppColors.grey500,
                      fontWeight: FontWeight.w500,
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
    final s = ResponsiveHelper.spacing(context, 16);
    return Container(
      color: Colors.white,
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.all(s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: theme.primaryColor),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text('찾아오는 길',
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: CommonWidgets.cardDecoration(),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildTransportRow(context, Icons.place,
                          _business!.address, _business!.detailAddress),
                    ),
                    IconButton(
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
                  ],
                ),
                if (_business!.phone != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTransportRow(context, Icons.phone,
                            FormatHelper.formatPhone(_business!.phone!), null),
                      ),
                      IconButton(
                        onPressed: () => _callPhone(_business!.phone!),
                        icon: Icon(Icons.call, size: 18, color: theme.primaryColor),
                        tooltip: '전화 걸기',
                      ),
                    ],
                  ),
                ],
                if (_business!.transportImageUrls != null &&
                    _business!.transportImageUrls!.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  LayoutBuilder(builder: (ctx2, constraints) {
                    final urls = _business!.transportImageUrls!;
                    final gap = ResponsiveHelper.spacing(context, 8);
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
                            margin: EdgeInsets.only(right: gap),
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
                if (_business!.transportDescription != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  _buildTransportRow(context, Icons.directions,
                      _business!.transportDescription!, null),
                ] else ...[
                  if (_business!.nearestStation != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    _buildTransportRow(context, Icons.subway,
                        _business!.nearestStation!,
                        _business!.walkingMinutes != null
                            ? '도보 ${_business!.walkingMinutes}분' : null),
                  ],
                  if (_business!.busInfo != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    _buildTransportRow(
                        context, Icons.directions_bus, '버스', _business!.busInfo),
                  ],
                ],
                if (_business!.latitude != null && _business!.longitude != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  RepaintBoundary(
                    child: GestureDetector(
                      onTap: () => _showFullMap(context),
                      child: SizedBox(
                        height: 180,
                        child: KakaoMapWidget(
                          latitude: _business!.latitude!,
                          longitude: _business!.longitude!,
                          placeName: _business!.name,
                          showControls: false,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => _showFullMap(context),
                      icon: Icon(Icons.zoom_out_map, size: 18),
                      label: Text('큰 지도 보기',
                          style: ResponsiveHelper.bodyStyle(context)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportRow(
      BuildContext context, IconData icon, String title, String? subtitle) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: theme.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: theme.primaryColor),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w500)),
              if (subtitle != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(subtitle,
                    style: ResponsiveHelper.smallStyle(context)
                        .copyWith(color: AppColors.grey600)),
              ],
            ],
          ),
        ),
      ],
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
      buttonText = '마감된 공고입니다';
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
      buttonText = '지원할 업무를 선택해주세요';
      isDisabled = true;
    } else {
      buttonText = '$count개 업무 선택됨  ·  지원하기';
      isDisabled = false;
    }

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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 14)),
              textStyle: ResponsiveHelper.bodyStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
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
                : Text(buttonText),
          ),
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

    DialogHelper.showSheet<void>(
      context,
      useRootNavigator: true,
      builder: (ctx) => Padding(
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
            Text('지원 준비가 필요해요',
                style: ResponsiveHelper.subtitleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text('일자리에 지원하려면\n아래 정보를 먼저 등록해주세요.',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(color: AppColors.grey500, height: 1.5)),
            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
            _buildReadinessRow(context, '신분 확인', '신분증 등록', hasId),
            // [PII-DOC-R1.5.2] 급여정보 줄을 뺐다. 이 시트는 "지원하려면
            //   먼저 등록해주세요"라고 말하는 자리이고, 급여정보는 더 이상
            //   지원의 조건이 아니다. 여기 남겨 두면 사실이 아닌 말이 된다.
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
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
                style:
                    TextButton.styleFrom(foregroundColor: AppColors.grey400),
                child: Text('나중에',
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(color: AppColors.grey400)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 지원 준비 바텀시트의 항목 행 — 상태 아이콘 (! 미완료 / ✓ 완료)
  /// 빈 원(radio_button_unchecked)은 체크박스처럼 보이므로 상태 아이콘으로 명확히 구분
  Widget _buildReadinessRow(
      BuildContext context, String label, String sublabel, bool isDone) {
    const successGreen = Color(0xFF22C55E);
    const pendingGrey = Color(0xFF9CA3AF);

    return Row(
      children: [
        // 상태 아이콘: 완료 = 초록 체크 원, 미완료 = 회색 ! 원
        Container(
          width: ResponsiveHelper.iconSize(context, 24),
          height: ResponsiveHelper.iconSize(context, 24),
          decoration: BoxDecoration(
            color: isDone
                ? successGreen.withValues(alpha: 0.12)
                : pendingGrey.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isDone
                ? Icon(Icons.check_rounded,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: successGreen)
                : Text('!',
                    style: TextStyle(
                      fontSize: ResponsiveHelper.iconSize(context, 13),
                      fontWeight: FontWeight.w700,
                      color: pendingGrey,
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
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w600)),
              Text(isDone ? '등록 완료' : '등록 필요',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: isDone ? successGreen : AppColors.grey500,
                  )),
            ],
          ),
        ),
        if (isDone)
          Text('완료',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                color: successGreen,
                fontWeight: FontWeight.w600,
              )),
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
                    Text(
                      work.workType,
                      style: ResponsiveHelper.titleStyle(context)
                          .copyWith(fontWeight: FontWeight.bold, height: 1.3),
                    ),

                    // ── 2. 한줄 설명 ────────────────────────
                    if (workType?.oneLineIntro != null &&
                        workType!.oneLineIntro!.isNotEmpty) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        workType.oneLineIntro!,
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(color: AppColors.grey600, height: 1.4),
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
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .primaryColor
                              .withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context)
                                .primaryColor
                                .withValues(alpha: 0.10),
                          ),
                        ),
                        child: Text(
                          workType.description!,
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            height: 1.6,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],

                    // ── 구분선 ──────────────────────────────
                    SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                    const Divider(height: 1, color: AppColors.grey100),
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
                            .copyWith(color: AppColors.grey500),
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
                        style: ResponsiveHelper.tinyStyle(context)
                            .copyWith(color: AppColors.grey400),
                      ),
                    ],
                    if (work.taxDeductionType != InsuranceRateModel.typeNone) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.receipt_long_outlined,
                              size: 12, color: AppColors.grey400),
                          const SizedBox(width: 4),
                          Text(
                            InsuranceRateModel.typeLabel(
                                work.taxDeductionType),
                            style: ResponsiveHelper.tinyStyle(context)
                                .copyWith(color: AppColors.grey400),
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
                      const Divider(height: 1, color: AppColors.grey100),
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
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(context).copyWith(
            color: AppColors.grey400,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 5)),
        Text(
          value,
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
    if (!meetsApplyPrerequisites(user, isFlexType: _to!.isFlexType)) {
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
    final List<({SlotModel? slot, WorkDetailModel work})> items = [];

    if (_to!.isFlexType) {
      for (final slot in _allSlots) {
        final key = _dateKey(slot.date);
        final wid = _flexSelected[key];
        if (wid == null) continue;
        final work = slot.workDetails.where((w) => w.id == wid).firstOrNull;
        if (work != null) items.add((slot: slot, work: work));
      }
      // 아무것도 선택 안 됐으면 현재 슬롯의 전체 업무로 (멀티 날짜 선택 없이 전체 지원)
      if (items.isEmpty && _currentWorkDetails.isNotEmpty) {
        for (final wd in _currentWorkDetails.where((w) => !w.isTimeExpired)) {
          items.add((slot: _currentSlot, work: wd));
        }
      }
    } else {
      final works = _contractSelected.isEmpty
          ? _workDetails
          : _workDetails.where((w) => _contractSelected.contains(w.id)).toList();
      for (final work in works) {
        items.add((slot: null, work: work));
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
        );
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
        ),
      );
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
        badgeColor  = AppColors.errorDark;
        badgeBgColor = AppColors.errorBg;
        mainMessage = '이번 지원은 확정되지 않았어요.';
        if (app.rejectMessage?.isNotEmpty == true) {
          subMessage = app.rejectMessage;
        }

      case AppStatus.canceled:
        badgeLabel  = '취소';
        badgeColor  = AppColors.grey600;
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
          badgeColor  = AppColors.grey600;
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
        badgeColor  = AppColors.grey600;
        badgeBgColor = AppColors.grey200;
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
            style: ResponsiveHelper.tinyStyle(context).copyWith(
              color: AppColors.grey400,
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
                child: Text(
                  mainMessage,
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
              subMessage,
              style: ResponsiveHelper.tinyStyle(context)
                  .copyWith(color: AppColors.grey500, height: 1.4),
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
    if (!meetsApplyPrerequisites(user, isFlexType: isFlex)) {
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
          DocumentAccessConsent.card(app.businessName),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
          onPressed: () => Navigator.pop(context, true),
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
        'documentAccessConsentVersion': DocumentAccessConsent.version,
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
    final confirmed = await DialogHelper.showCancelConfirm(
      context,
      title: '초대 거절',
      message: '초대를 거절하시겠습니까?',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isDecliningInvite = true);
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableDeclineTOInvitation');
      await callable.call({'applicationId': widget.myApplication!.id});
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
