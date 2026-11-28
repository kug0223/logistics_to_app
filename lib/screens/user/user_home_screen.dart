import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/fcm_service.dart';

import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/id_card_access_request_model.dart';
import '../../models/core/legal_readiness.dart';
import '../../models/core/slot_model.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_data.dart';
import '../../models/core/user_model.dart';
import '../../models/core/user_region.dart';
import '../../models/ui/pending_id_request_surface.dart';
import '../../models/ui/pending_termination_surface.dart';
import '../../utils/format_helper.dart';
import '../../utils/expected_daily_wage.dart';
import '../../utils/text_layout.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/concept_tokens.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/tour_helper.dart';
import '../../widgets/auth/account_status_banner.dart';
import '../../widgets/common/legal_task_card.dart';
import '../../widgets/common/business_selector_sheet.dart';
import '../../widgets/common/notification_badge.dart';
import '../../widgets/common/alfit_wordmark.dart';
import '../../widgets/user/cards/job_image_placeholder.dart';
import '../common/notification_screen.dart';
import '../common/document_management_screen.dart';
import '../../widgets/home/start_readiness_card.dart';
import '../../main.dart' show openHomeRegionSetup;
import '../common/job_posting_screen.dart';
import '../../utils/navigation_helper.dart';
import '../common/tour_screen.dart';
import 'attendance_check_screen.dart';
import 'checkin_contract_gate.dart';
import '../contract/contract_sign_screen.dart';
import 'dialogs/my_requests_dialog.dart';
import 'my_applications_screen.dart';
import 'user_tab_scope.dart';
import '../../widgets/calendar/app_calendar.dart';
import 'package:table_calendar/table_calendar.dart' show AvailableGestures;
import '../../utils/calendar_helper.dart';
import 'income_detail_screen.dart';
import '../auth/pass_auth_recovery_screen.dart';
import '../../services/payroll_correction_service.dart';
import '../../services/home_recommend_cache.dart';
import '../../services/firestore_service.dart' show HomeBundleOutcome, WorkerHomeBundle;
import '../legal/legal_consent_reads.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../models/core/renewal_proposal_model.dart';
import 'renewal_proposal_screen.dart';
import 'home_recruitable_projection.dart';
import 'user_home_reads.dart';

// ── 지원자 홈 화면 ────────────────────────────────────────────────
class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key, this.reads, this.clock, this.tourCompleted, this.recommendCache});

  /// [impl_12 · P2] 추천 표시 캐시(RAM). production 은 null → [HomeRecommendCache.shared].
  final HomeRecommendCache? recommendCache;

  /// [R7-P2-1 P21-E] 홈이 나가서 읽는 **원시 외부 호출**만 모은 경계.
  ///   production 은 null — 기존 `FirestoreService` 인스턴스를 그대로 쓴다.
  ///   파싱·Hero 판정·주간 7일·집계·문구는 전부 이 화면에 남는다.
  final UserHomeReads? reads;

  /// [R7-P2-1 잔여] "지금"의 출처. production 은 null → `DateTime.now`.
  ///   출퇴근 화면과 **같은 시각**으로 두 화면의 날짜 판정을 맞대 보기 위한
  ///   자리다. 화면 로직은 그대로 지난다.
  final DateTime Function()? clock;

  /// [PERF-L3] 홈 투어를 이미 봤는지(로컬 저장소 한 줄). production 은 null → `TourHelper`.
  ///   **데이터의 전제가 아니다** — 이 future 가 늦거나 던져도 홈 읽기는 이미 출발해 있다.
  final Future<bool> Function()? tourCompleted;

  /// [판정290 D290-02 · 시험 전용] 위쪽 변화 보정 계수 — scheduled(예약) · applied(실행) · discarded(실행 직전 재검사 실패) ·
  ///   noop(순변화 없음/이미 그 위치). 운영 동작에 쓰지 않는다(시험이 비운다).
  @visibleForTesting
  static final Map<String, int> debugZoneAnchorStats = <String, int>{};
  static void _stat(String k) => debugZoneAnchorStats[k] = (debugZoneAnchorStats[k] ?? 0) + 1;

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen>
    with WidgetsBindingObserver {
  late final UserHomeReads _reads = widget.reads ?? UserHomeReads.of();
  DateTime _now() => (widget.clock ?? DateTime.now)();
  List<ApplicationModel> _applications = [];
  List<AttendanceModel> _attendances = [];
  List<TOModel> _publishedTos = [];

  /// [R8-P7.4] 공고 목록을 **읽지 못했다**.
  ///
  /// `_publishedTos`가 비어 있는 이유가 "공고가 없어서"인지 "못 읽어서"인지
  /// 구분한다. 구분하지 않으면 조회 실패가 "지원 가능한 일자리가 없어요"로
  /// 보이고, 사용자는 앱이 정상이라고 믿은 채 공고를 놓친다.
  bool _postingsFailed = false;

  /// [R7-P2-1 후속 P21-E] 이번 달 근태를 **읽지 못했다**.
  ///
  ///   수입의 `근무 완료`·`정산 중`·`예상 수입` 은 근태에서 나온다.
  ///   조회가 실패해도 지금까지는 빈 목록으로 계산돼 `0원` 과
  ///   "아직 이번 달 수입이 없어요" 가 나왔다 — **못 읽은 것을 번 돈이
  ///   없다고 말한 것**이다. 근로자는 앱이 정상이라 믿고 미지급을 놓친다.
  ///   (지원 내역은 `_homeLoadFailed` 가 이미 같은 구분을 한다.)
  bool _attendancesFailed = false;

  /// [R7-P2-1 잔여] **어제 달**의 근태 꼬리.
  ///
  ///   자정을 넘겨 계속되는 근무의 기록은 `workDate` 가 **어제**다. 달의
  ///   1일에는 그 어제가 지난달이라 이번 달 조회에 들어오지 않는다 —
  ///   그날만 같은 조회를 한 번 더 한다(같은 CF·같은 self-uid 계약).
  ///   polling 도 listener 도 아니고, 1일이 아니면 호출 자체가 없다.
  List<AttendanceModel> _prevMonthTail = const [];

  /// 어제 근무의 퇴근 여부를 **판단할 수 없다**.
  ///
  ///   근태를 못 읽으면 "퇴근이 남지 않았다"고 말할 수 없다. 침묵하면
  ///   미퇴근이 `missed_checkout` 으로 자동 처리돼 임금 분쟁이 된다.
  bool _overnightUnknown = false;

  /// [CONTRACT-DISPATCH-B4] 이번 로드의 내 계약 목록. null = 못 읽음(동의로 치지 않는다).
  List<EmploymentContractModel>? _contracts;
  /// businessId → BusinessModel 캐시 — 사업장 이미지·혜택 정보 표시용
  Map<String, BusinessModel> _businessCache = {};
  /// [E1-HOME-FIRST-ENTRY] **읽기 전부터 LOADING 이다.**
  ///
  ///   false 로 시작하면 `initState` 와 첫 `_loadHomeData()` 사이의 창이
  ///   통째로 `SUCCESS_ZERO` 로 보인다 — 지원서 8건·오늘 출근 근무가 있는
  ///   사용자에게 `아직 지원한 일자리가 없어요` 라고 말한 그 창이다.
  ///   로드는 `initState` 의 postFrame 콜백에서, 그것도
  ///   `await TourHelper.isCompleted(...)` 뒤에야 시작한다(DEV 에뮬레이터
  ///   실측 969ms, 저장소가 느리면 더 길다). 그 사이를 빈 결과로 단정하지
  ///   않는다.
  ///
  ///   영원히 로딩에 갇히지 않는 근거: 이 화면은 `AuthWrapper` 가
  ///   `currentUser != null` 일 때만 그리므로 `_loadHomeData()` 의
  ///   `uid == null` 조기 반환 경로는 도달하지 않는다. 그 경로가 실제로
  ///   관측되면 그때 트리거를 복구한다(추정으로 넣지 않는다).
  bool _isLoadingData = true;

  // ── [PERF-P1 · 판정289 §4 · 판정290] 「필수응답 + 약속」 구역의 첫 표시 조정 ─────────────────
  //   출처 7(자정 퇴근 · 신분증 요청 · 계약해지 · 연장 제안 · 서류 보완 · 약관 · 약속)이 모두 terminal
  //   (성공 0/비0 · ERROR · PARTIAL)이 되면 구역을 **한 번에** 보인다. 그 전에는 약속 자리 뼈대 하나만 둔다.
  //   600ms 는 첫 뼈대 프레임 기준 **최초 표시 잠정 상한**이다 — 최소 대기·조회 timeout·정상0 기한이 아니다.
  //   상한이 지나면 끝난 것은 보이고 끝나지 않은 것은 '확인 중'으로 남는다(원 조회는 계속 · 늦은 응답 반영).
  //   긴급 행동(자정 퇴근 · 계약해지 응답 · 오늘 약속)이 확정되면 다른 출처를 기다리지 않는다.
  //   최초 1회 조정이다 — 재조회에는 다시 걸지 않는다.
  static const Duration _kRevealCap = Duration(milliseconds: 600);
  bool _zoneRevealed = false;
  bool _revealCapPassed = false;
  Timer? _revealTimer;

  /// 1라운드(지원·근태·신분증·계약)가 **이 uid 로** 한 번이라도 끝났다(성공·실패 모두 terminal).
  ///   재조회 중에도 true 로 남아 마지막 성공 값을 내리지 않는다 — 같은 데이터에 구역이 접혔다 펼쳐지지 않는다.
  bool _mainRoundDone = false;
  String? _mainRoundUid;

  /// `_initSeenIds`(SharedPreferences)가 끝났다 — 새 확정(A)이 보였다 사라지지 않게 약속 출처는 이것도 본다.
  bool _seenIdsLoaded = false;

  /// [판정290 D290-01] **현재 조회**가 실패한 출처. 실재 카드는 성공해 읽은 근거가 있을 때만 그대로 그리고,
  ///   실패는 출처·건수를 말하지 않는 일반 한 줄(「일부 정보를 확인하지 못했어요 · 다시 시도」)만 말한다.
  bool _idRequestsFailed = false;
  bool _renewalProposalsFailed = false;
  bool _retryingFailedSources = false;

  /// 약관 카드가 알려 온 마지막 상태(null = 아직). error 도 terminal 이다(R7-LEGAL 숨김 유지 · 일반 행 대상 아님).
  LegalReadiness? _legalReadiness;

  // ── [판정290 D290-02] 위쪽 구역 변화 때 보던 내용 유지(조건부) ─────────────────────────────
  //   구역 전체가 이미 화면 위로 지나갔고 사용자가 조작하지 않을 때만, 구역 아래끝 표지의 **실제 순변화량**만큼
  //   다음 프레임에 한 번 offset 을 옮긴다. 새 카드를 찾아가지 않는다(animateTo·ensureVisible·초점 이동 0).
  final ScrollController _homeScroll = ScrollController();
  final GlobalKey _zoneEndKey = GlobalKey(debugLabel: 'worker-home-zone-end');
  /// 보정 기준(anchor) = 구역 **아래의 첫 상시 블록**(통합 날짜 영역). 구역 끝 표지는 '구역이 화면 위로 지나갔나'만 본다 —
  ///   표지 자체를 기준으로 쓰면 구역 마지막 칸의 종류에 따라 바뀌는 다음 블록 간격(12/24)이 빠진다.
  final GlobalKey _anchorKey = GlobalKey(debugLabel: 'worker-home-zone-anchor');
  int _pointersDown = 0;
  int _inputEpoch = 0;
  bool _userScrolling = false;
  bool _selfCorrecting = false;
  _ZoneAnchor? _zoneAnchor;

  // ── [impl_12 · P2 · 판정289 §6 C289-05 · 판정291 D291-02/C291-P2] 추천 '마지막 성공' 표시 ─────────────────
  //   첫 1라운드 전(= 아직 live 결과 없음)·날짜 미선택일 때만, 같은 uid·범위의 마지막 성공 추천(최대 2장 · 표시 문구 +
  //   공개 대표사진)을 '마지막 확인 HH:MM · 확인 중'과 함께 보인다. live 결과가 오면 그것으로 바뀐다 —
  //   live 가 0장·실패·부분이면 캐시는 보이지 않는다(정상0·오류를 캐시로 가리지 않는다). 누르면 아무 일도 없다(live 확인 전).
  //   홈 원천 목록(_applications·_publishedTos 등)에 넣지 않는다 — 표시 전용 경로.
  late final HomeRecommendCache _recCache = widget.recommendCache ?? HomeRecommendCache.shared;

  // ── [PERF-L9 · impl_15] 묶음 경로의 약관 준비 — 첫 1라운드 묶음이 함께 읽어 약관 카드에 넘긴다 ─────────────
  //   약관 카드는 자기 첫 조회를 이 future 로 받는다(같은 값 · 따로 호출 0). 그 뒤의 조회(앱 복귀·동의 뒤)는 원래 경로다.
  Completer<LegalReadiness>? _bundleLegal;
  bool _bundleLegalHandedOut = false;

  Future<LegalReadiness> _legalLoader() {
    final c = _bundleLegal;
    if (c != null && !_bundleLegalHandedOut) {
      _bundleLegalHandedOut = true;
      return c.future;
    }
    return (_reads.legalReadiness ?? LegalConsentReads.of().readiness)();
  }

  /// 묶음의 약관 결과를 카드에 넘긴다. null(구서버 폴백 · 묶음 전체 실패) = 카드가 원래 경로로 직접 읽는다.
  void _resolveBundleLegal(HomeBundleOutcome<LegalReadiness>? o) {
    final c = _bundleLegal;
    if (c == null || c.isCompleted) return;
    if (o == null) {
      c.complete((_reads.legalReadiness ?? LegalConsentReads.of().readiness)());
    } else if (o.ok) {
      c.complete(o.value!);
    } else {
      c.completeError(o.error!); // 개별 호출 실패와 같다 — 카드는 error(숨김 · R7-LEGAL)
    }
  }
  HomeRecommendSnapshot? _recSnapshot;

  HomeRecommendScope _recScope(UserModel user) {
    String env = '';
    try {
      env = Firebase.app().options.projectId;
    } catch (_) {}
    final r = user.homeRegion;
    return HomeRecommendScope(
      env: env,
      role: 'USER',
      regionKey: r == null ? '' : '${r.city}|${r.district ?? ''}',
      queryKey: 'home-recommend-v1:unselected',
    );
  }

  // ── 초대 카운트 (INVITED 상태 지원서 수) ────────────────────────
  int get _invitedCount =>
      _applications.where((a) => a.status == AppStatus.invited).length;

  // ── 캐시 필드 — _applications/_attendances 변경 시에만 재계산 ────────
  // [판정285 C285-03] 옛 `이번 주 일정`(오늘~+6 확정·지원 중 Set)과 날짜띠 확정 Set(workDate 만)은 지웠다 —
  //   표시 날짜마다 [_scheduleOn] 하나가 점과 인라인 본문을 함께 계산한다(다른 범위의 캐시 재사용 0).
  List<ApplicationModel> _cachedRecentApplications = [];
  int _cachedPendingCount = 0;
  int _cachedConfirmedCount = 0;
  int _cachedContractPendingCount = 0;
  Map<String, int> _cachedWorkTypeStats = {};
  // [판정286] 날짜띠·날짜 시트·선택일 요약의 공고 수 표시를 없앴다 — 날짜 영역은 내 일정만 말한다.
  //   날짜별 공고 수 캐시(_toDateCounts)도 읽는 곳이 없어 지웠다. 추천 후보 projection(_recruitable)은 그대로다.

  /// [R7-P4.4E.8A] 날짜별 모집 가능한 공고 — **날짜칩과 추천 목록의 공용 결과**.
  ///   두 곳이 각각 판단하면 "칩은 1인데 목록은 0" 같은 어긋남이 생긴다.
  HomeRecruitableProjection? _recruitable;

  /// [BL287-01] 같은 입력으로 **약속 충돌만 판정하지 않은** projection(`commitmentsKnown: false`).
  ///   두 projection 의 차이 = 확정 근무와 시간이 겹쳐 빠진 공고다 — 다른 제외 사유(마감·관계·슬롯)는 양쪽이 같다.
  ///   새 조회 0(이미 읽은 공고·지원·슬롯만). 지원 목록을 못 읽었으면 만들지 않는다(겹침을 말할 근거 없음).
  HomeRecruitableProjection? _recruitableIgnoringCommitments;

  /// 내가 **활성 지원을 가진 flex 공고**의 슬롯만 담는다.
  ///   그 날짜에 형제 근무가 남아 있는지는 슬롯을 봐야 정확히 알 수 있고,
  ///   관계가 없는 날짜는 애초에 지울 이유가 없어 읽지 않는다 —
  ///   후보 공고 수만큼 읽기가 늘어나는 구조(N+1)를 만들지 않는다.
  final Map<String, List<SlotModel>> _slotsByToId = {};

  /// 이미 슬롯을 시도한 공고 id — 같은 로드에서 두 번 읽지 않는다.
  final Set<String> _slotFetchAttempted = {};
  // STATE C — Hero 7일 스트립의 시작일 (기본: 오늘)
  // 날짜 더보기 캘린더에서 범위 외 날짜 선택 시 해당 날짜로 이동
  late DateTime _stripStart;
  // STATE C — 선택된 날짜 (null = 미선택, 선택일 요약·CTA 숨김)
  // [판정285 §4] 같은 날 재탭은 선택 유지 — 해제는 `날짜 해제` 한 곳뿐이다.
  DateTime? _selectedDateChip;

  /// [판정285 §3 · C285-03] 한 날짜의 내 일정 — 날짜띠 점과 선택일 인라인 본문이 **같은 결과**를 읽는다.
  ///
  ///   확정 근무 = `CONFIRMED`·`CONTRACT_PENDING`(AppStatus.confirmedStatuses) 중 그날 **실제 근무일**
  ///     (`isWorkingOnDate` — 장기의 휴무일 제외·추가근무/효력일 포함). 종료가 그날 이미 발효된 장기는 뺀다.
  ///   지원 중 = `PENDING` 만(INVITED 는 초대 배너 · 합치지 않는다). 장기는 `isScheduledOnDate` 의
  ///     `desiredStartDate ?? workDate` 당일만 — 매주 반복시키지 않는다. 근무 약속으로 부르지 않는다.
  ///   정렬 = 상태 안에서 시작 시각 순(확정이 먼저 — 인라인이 이어 붙인다).
  ///   표시 범위를 미리 정하지 않는다 — 띠가 어느 주·달로 옮겨 가도 그 날짜로 다시 계산한다.
  ({List<ApplicationModel> confirmed, List<ApplicationModel> pending}) _scheduleOn(DateTime dayKey) {
    final confirmed = <ApplicationModel>[];
    final pending = <ApplicationModel>[];
    for (final a in _applications) {
      if (AppStatus.confirmedStatuses.contains(a.status)) {
        if (a.isLongTermApplication && a.isExitEffectiveOn(dayKey)) continue;
        if (a.isWorkingOnDate(dayKey)) confirmed.add(a);
      } else if (a.status == AppStatus.pending) {
        if (a.isScheduledOnDate(dayKey)) pending.add(a);
      }
    }
    int byStart(ApplicationModel x, ApplicationModel y) => x.startTime.compareTo(y.startTime);
    confirmed.sort(byStart);
    pending.sort(byStart);
    return (confirmed: confirmed, pending: pending);
  }

  /// [판정285 §4] 지원 목록 읽기는 한 번에 최대 200 건이다(application_firestore `limit:200`).
  ///   그만큼 받았으면 더 있을 수 있다 — 날짜 요약을 완전한 목록이라고 말하지 않는다.
  static const int _kApplicationsReadLimit = 200;
  bool get _applicationsMaybePartial => _applications.length >= _kApplicationsReadLimit;

  // ── Priority Hero 캐시 ─────────────────────────────────────────
  // STATE B: 오늘 확정 근무 (출퇴근 CTA 표시)
  ApplicationModel? _heroTodayApp;
  // STATE A: 72시간 이내 미확인 신규 확정
  ApplicationModel? _heroNewConfirmApp;

  // STATE A "미확인" 추적 — SharedPreferences에 persist (앱 재시작 후에도 유지)
  Set<String> _seenConfirmIds = {};
  static const _kSeenKey = 'seen_confirm_ids_v1';

  /// [R7-P4.4E.8A] 내가 활성 지원을 가진 **flex 공고의 슬롯만** 읽는다.
  ///
  ///   왜 전부 읽지 않는가 — 관계가 없는 날짜는 지울 이유가 없으므로 슬롯을
  ///   볼 필요가 없다. 후보 공고마다 읽으면 공고 수만큼 읽기가 늘어난다.
  ///   여기서 늘어나는 읽기는 **내가 지원한 flex 공고 수**(보통 0~2)다.
  ///
  ///   실패는 삼키고 남긴다 — 못 읽은 것을 "모집 없음" 으로 바꾸지 않는다.
  ///
  ///   [SIM-FULL-FLEX-HOME] 서버가 **FULL 로 적은** flex 공고도 읽는다.
  ///   관계가 없으면 슬롯을 모르고, 모르는 공고는 남기므로 정원이 찬 공고가
  ///   "모집중" 카드로 보였다(DEVICE 10-18, 상세는 "인원 마감"). status 를
  ///   정답으로 쓰지는 않는다 — 읽은 슬롯으로 projection 이 판정하고, status 가
  ///   낡았으면(취소 직후 등) 그대로 남는다. 늘어나는 읽기는 FULL 로 표시된
  ///   flex 후보 수(회차당 1회)이고, ACTIVE 공고는 여전히 읽지 않는다.
  Future<void> _loadRelationSlots(bool Function() superseded) async {
    final flexIds = <String>{};
    for (final to in _publishedTos) {
      if (!to.isFlexType) continue;
      if (_slotFetchAttempted.contains(to.id)) continue;
      final hasActive = _applications.any((a) {
        if (a.toId != to.id) return false;
        if (a.isExitDecided) return false;
        final s = a.status;
        return s == AppStatus.pending ||
            s == AppStatus.contractPending ||
            s == AppStatus.confirmed ||
            s == AppStatus.invited;
      });
      if (hasActive || to.status == TOStatus.full) flexIds.add(to.id);
    }
    if (flexIds.isEmpty) return;

    // [R8-PERFORMANCE.2] 공고마다 한 라운드씩 줄 서 있었다.
    //
    //   각 조회의 입력은 toId 하나뿐이고 서로의 결과를 보지 않는다. 결과도
    //   전부 모인 뒤에 한 번 `_rebuildCaches()` 로 들어가므로 중간 결과를
    //   화면에 먼저 반영하는 것도 아니었다 — 순서대로 기다릴 이유가 없었다.
    //   읽기 수는 그대로다(같은 N 개). 바뀌는 것은 라운드 수뿐이다.
    //   N 은 후보 공고 수가 아니라 **내가 활성 지원을 가진 flex 공고 수**다
    //   (DEV 실측 최대 2). 그래서 동시 요청을 따로 제한하지 않는다.
    //
    //   결과는 **지역 맵에 모은 뒤** 한 번에 반영한다. 화면 필드에 바로 쓰면
    //   낡은 회차의 응답이 새 회차가 시작된 뒤에 도착해 그 자리에 끼어든다 —
    //   Firestore `get` 은 취소할 수 없으므로 guard 는 **적용만** 막는다.
    //   (직렬 루프는 그 사이에 멈출 수 있었지만, 멈추기 전까지 쓴 값은
    //    그대로 남겼다. 모아서 반영하면 그 잔재도 사라진다.)
    //
    //   실패는 공고별로 끊는다. 실패한 공고는 맵에 들어가지 않고, 그것은
    //   `모집 없음`이 아니라 `모른다`로 남는다 —
    //   `HomeRecruitableProjection._flexRecruitableOn` 이 슬롯을 모를 때
    //   후보를 지우지 않는다. 한 공고의 실패로 다른 공고가 사라지지 않는다.
    final loaded = <String, List<SlotModel>>{};
    for (final id in flexIds) {
      _slotFetchAttempted.add(id);
    }
    await Future.wait(flexIds.map((id) async {
      try {
        loaded[id] = await _reads.slotsForTO(id);
      } catch (e) {
        debugPrint('⚠️ 홈 슬롯 로드 실패($id): $e');
      }
    }));
    if (!mounted || superseded()) return;
    setState(() {
      _slotsByToId.addAll(loaded);
      _rebuildCaches();
    });
  }

  void _rebuildCaches() {
    final sorted = [..._applications]
      ..sort((a, b) => b.workDate.compareTo(a.workDate));
    _cachedRecentApplications = sorted.take(3).toList();

    final now = _now();
    final today = FormatHelper.toKstDate(now);

    // ── Priority Hero 캐시 계산 ──────────────────────────────────
    // STATE B: 오늘 확정 근무 존재 여부 (출퇴근 CTA 최우선)
    //
    // [R7-P2-1 P21-H] 예전에는 `toKstDate(workDate) == today` 만 봤다.
    //   장기 근무의 `workDate` 는 **계약 시작일(고정값)** 이라, 시작일 하루를
    //   빼면 오늘 실제로 일하는 장기 근무자에게 Hero 가 비어 버렸다 —
    //   출퇴근 CTA 를 홈에서 잃는다. 같은 화면의 날짜띠 점([_scheduleOn])
    //   과 출근 화면(`attendance_check_screen`)은 이미 `isWorkingOnDate` 를 쓴다
    //   (그 화면 주석이 같은 이유를 적고 있다). 한 화면이 두 가지로 말하지 않게
    //   **같은 canonical 술어**로 맞춘다 — 휴무일·추가근무·퇴사일이 함께 반영된다.
    final todayList = _applications.where((a) {
      if (!AppStatus.confirmedStatuses.contains(a.status)) return false;
      return a.isWorkingOnDate(today);
    }).toList();
    // [DEVICE-MISMATCH-FIX] 오늘 근무가 여럿이면 **아직 끝나지 않은** 근무가
    //   현재 할 일이다(가장 이른 것부터). 모두 끝났으면 가장 최근 근무를
    //   보인다 — 오전에 놓친 근무가 오후에 마친 근무를 가리지 않게 한다.
    //   예전에는 목록 순서 그대로 first 였다.
    todayList.sort((a, b) {
      final ea = a.hasShiftEndedAt(now);
      final eb = b.hasShiftEndedAt(now);
      if (ea != eb) return ea ? 1 : -1;
      return ea
          ? b.startTime.compareTo(a.startTime)
          : a.startTime.compareTo(b.startTime);
    });
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
    //
    // [R7-P4.4E.8A] 날짜칩과 추천 목록이 **같은 projection 하나**를 본다.
    //   예전에는 두 곳이 각각 판단했고, 둘 다 지원서가 있으면 `to.id` 로
    //   **공고 전체를 버렸다**. 그래서 flex 공고의 10/05 에 지원하면
    //   10/06~10/11 의 다른 날짜 모집까지 홈에서 사라졌다(DEV 실측: 6일 ×
    //   2업무 = 12건). 이제 관계가 있는 **그 wdId 만** 빠지고 형제는 산다.
    final cutoff = today.add(const Duration(days: 60));
    //
    // [R7-APPLICATION-LIFECYCLE.1C] 이미 확정된 근무와 시간이 겹치는 관계는
    //   서버가 지원을 거부한다. 그래서 `지원 가능한 일자리` 수치에서도
    //   빠져야 한다 — 추가 쿼리는 없다(`_applications` 를 그대로 쓴다).
    //   지원 목록을 못 읽었으면(`_homeLoadFailed`) 겹침을 판정할 수 없으므로
    //   후보를 지우지 않고, 그 사실은 기존 ERROR/PARTIAL 배너가 말한다.
    _recruitable = HomeRecruitableProjection.build(
      publishedTos: _publishedTos,
      myApplications: _applications,
      today: today,
      cutoff: cutoff,
      slotsByToId: _slotsByToId,
      commitmentsKnown: !_homeLoadFailed,
    );
    _recruitableIgnoringCommitments = _homeLoadFailed
        ? null
        : HomeRecruitableProjection.build(
            publishedTos: _publishedTos,
            myApplications: _applications,
            today: today,
            cutoff: cutoff,
            slotsByToId: _slotsByToId,
            commitmentsKnown: false,
          );
  }

  /// [BL287-01] 선택일에 **확정 근무와 시간이 겹쳐서** 빠진 공고 수 — 확인된 사유일 때만 센다.
  ///   = 겹침을 보지 않았다면 그날 후보였는데 실제 후보에는 없는 공고(같은 후보 필터 · 같은 날짜 필터).
  ///   로딩·공고 조회 실패·지원 조회 실패/잔존·200 건 상한(일부만 읽음)이면 0 — 사유를 말하지 않는다.
  int _conflictExcludedOn(UserModel user) {
    if (_selectedDateChip == null) return 0;
    if (_isLoadingData || _postingsFailed || _homeLoadFailed || _applicationsMaybePartial) return 0;
    final free = _recruitableIgnoringCommitments;
    if (free == null || _recruitable == null) return 0;
    final shown = _getRecommendedTos(user).map((t) => t.id).toSet();
    return _getRecommendedTos(user, projection: free).where((t) => !shown.contains(t.id)).length;
  }

  // ── [DS-03] 신분증 열람 요청 진입점 ────────────────────────────
  // 노출 판단은 요청 컬렉션 조회 결과만 사용한다.
  // notification 존재 여부·개수는 판단에 쓰지 않는다 — 알림을 지워도
  // 처리하지 않은 요청은 홈에서 계속 발견할 수 있어야 한다.
  PendingIdRequestSurface _idRequestSurface = PendingIdRequestSurface.empty;

  /// [PII-DOC-R1.6.1] 근로자가 해결해야 할 서류 보완 — 지급이 막힌 것 포함.
  ///
  ///   source는 알림이 아니라 서버의 OPEN correction이다. 알림을 읽거나
  ///   지워도, 앱을 다시 켜도 할 일은 남는다.
  DocumentCorrectionSurface _correctionSurface =
      DocumentCorrectionSurface.empty;
  bool _correctionsLoaded = false;
  /// [H6-E] 재시도 중 — 같은 탭을 두 번 눌러 원격 호출을 겹치지 않게 한다.
  bool _isReloadingCorrections = false;

  /// [RENEWAL-PROPOSAL-COMMITMENT] 지금 응답할 수 있는 연장 제안.
  ///
  ///   출처는 제안 문서다 — 알림을 읽거나 지워도 할 일은 남는다.
  List<RenewalProposalModel> _renewalProposals = const [];
  bool _renewalProposalsLoaded = false;
  // 첫 조회 완료 전(LOADING)에는 아무것도 그리지 않는다.
  // 대부분의 사용자는 요청이 0건이라 skeleton을 두면 빈 자리만 깜빡인다.
  bool _idRequestsLoaded = false;

  late final VoidCallback _onFcmRefresh;
  bool _isLoadingHomeData = false;

  /// [PREDEVICE-WORKER-ERROR-NOT-ZERO] 마지막 홈 조회가 실패했는가.
  ///
  /// 이 화면은 지금까지 조회 실패를 빈 목록으로 받아 "검토중 0 · 확정 0"으로
  /// 그렸다. 0건과 못 불러온 것은 근로자에게 전혀 다른 뜻이다 —
  /// 앞은 지원하러 가라는 말이고, 뒤는 다시 시도하라는 말이다.
  ///   LOADING          _isLoadingData          ← **읽기 전 포함**(초기값 true)
  ///   ERROR            _homeLoadFailed && _applications.isEmpty && !_isLoadingData
  ///   PARTIAL(stale)   _homeLoadFailed && _applications.isNotEmpty
  ///   SUCCESS_ZERO     !_homeLoadFailed && _applications.isEmpty && !_isLoadingData
  ///   SUCCESS_NONZERO  !_homeLoadFailed && _applications.isNotEmpty
  ///
  /// [E1-HOME-FIRST-ENTRY] 예전에는 "아직 읽지 않음" 이 이 표에 없었고,
  ///   그래서 첫 프레임이 SUCCESS_ZERO 로 떨어졌다. UNKNOWN != EMPTY.
  bool _homeLoadFailed = false;
  DateTime? _lastAutoRefreshAt;

  @override
  void initState() {
    super.initState();
    // Hero 7일 스트립: 오늘부터 시작 (과거 없음)
    final now = _now();
    _stripStart = FormatHelper.toKstDate(now);
    WidgetsBinding.instance.addObserver(this);
    _onFcmRefresh = () { if (mounted) _autoRefresh(); };
    FCMService().addUserDataRefreshListener(_onFcmRefresh);
    // [WORKER-HOME-STARTUP.23] 출근부 PDF 한글 폰트 미리 읽기를 뺐다 — 근로자 화면은 출근부 PDF 를
    //   만들지 않는다(쓰는 곳은 관리자 화면뿐이고, 쓸 때 _loadFonts 가 스스로 읽는다).
    //   여기서는 큰 TTF 두 개를 메인 스레드에서 해석해 첫 화면 직후 홈 로드 시작을 ~1.2초 밀었다(LOCAL 디버그 로그).
    _initSeenIds(); // STATE A "미확인" 목록 복원 (SharedPreferences)
    // [PERF-L9 · impl_15] 묶음 경로면 첫 약관 준비도 묶음이 읽는다(카드가 첫 프레임에 이 future 를 받는다).
    if (_reads.homeBundle != null) {
      _bundleLegal = Completer<LegalReadiness>();
      _bundleLegal!.future.ignore();
    }
    // [impl_12 · P2] 첫 프레임 전에 동기로 본다(기다리지 않음 · RAM 거울).
    final recUser = context.read<UserProvider>().currentUser;
    if (recUser != null) _recSnapshot = _recCache.peek(uid: recUser.uid, scope: _recScope(recUser));
    // [PERF-L3] 홈 읽기는 투어 확인(SharedPreferences)을 기다리지 않는다.
    //   예전에는 투어 완료 여부를 await 한 뒤에야 `_loadHomeData()` 를 불렀다 — 기기에서
    //   initState → 첫 읽기 사이 969ms 가 이 대기였다(user_home_first_entry_state_test 머리 주석).
    //   그 future 가 던지면 홈 읽기가 아예 시작하지 않았다. 관리자 홈 H2 와 같은 순서다:
    //   데이터 먼저 출발 → 투어는 따로 확인 · 실패는 삼키고 완료로 저장하지 않는다.
    //   홈 읽기의 오류 안내(토스트)는 투어 판정·투어가 끝난 뒤에 보인다(`_toastAfterTour`).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tourSettled = Completer<void>();
      _tourSettled = tourSettled.future;
      // [PERF-P1] t0 = 첫 뼈대 프레임. 상한은 한 번만 건다(권한창·투어로 늘리지 않는다).
      _revealTimer = Timer(_kRevealCap, () => _zoneSetState(() => _revealCapPassed = true));
      _loadHomeData();
      unawaited(() async {
        try {
          final tourDone = await (widget.tourCompleted ??
              () => TourHelper.isCompleted(TourHelper.userHome))();
          if (!tourDone && mounted) await _showTourDialog();
        } catch (e) {
          debugPrint('⚠️ 홈 투어 확인 실패(투어 생략 · 완료 저장 안 함): $e');
        } finally {
          tourSettled.complete();
          if (identical(_tourSettled, tourSettled.future)) _tourSettled = null;
        }
      }());
    });
  }

  /// [PERF-L3] 투어 판정·투어 화면이 끝나면 완료되는 future. null = 기다릴 투어가 없다.
  Future<void>? _tourSettled;

  /// [PERF-L3] 홈 읽기 오류 안내 — 투어가 떠 있는 동안 생긴 오류는 투어가 닫힌 뒤에 보인다.
  ///   오류 **상태**(`_homeLoadFailed`)는 호출부가 즉시 기록한다. 늦추는 것은 토스트뿐이다.
  void _toastAfterTour(String message) {
    final gate = _tourSettled;
    if (gate == null) {
      ToastHelper.showError(message);
      return;
    }
    unawaited(gate.then((_) {
      if (mounted) ToastHelper.showError(message);
    }));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FCMService().removeUserDataRefreshListener(_onFcmRefresh);
    _revealTimer?.cancel();
    _zoneAnchor = null;
    _homeScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoRefresh();
  }

  void _autoRefresh() {
    // [R7-P4.4B] 여기만 실제 시계다 — 30초 쿨다운은 **경과 시간** 측정이라
    //   주입 시계를 쓰면 테스트에서 시간이 흐르지 않아 영원히 막힌다.
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
      _zoneSetState(() {
        _seenConfirmIds = ids.toSet();
        // seenIds 로드 후 Hero 캐시 재계산 — STATE A 노출 여부 갱신
        _rebuildCaches();
        _seenIdsLoaded = true;
      });
    } catch (_) {
      // SharedPreferences 실패 시 빈 set 유지 (STATE A가 과도 표시될 수 있으나 치명적이지 않음)
      // [PERF-P1] 실패도 terminal — 약속 출처를 영원히 '확인 중'으로 두지 않는다.
      if (mounted) _zoneSetState(() => _seenIdsLoaded = true);
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

  /// [R7-P2-1 P21-E] 홈 로드의 늦은 응답 가드.
  ///
  ///   `_loadHomeData` 를 깨우는 경로가 여럿이다: initState · FCM · 앱 복귀 ·
  ///   당겨서 새로고침 · 각 목적지에서 돌아올 때 · 재시도 버튼.
  ///   가드가 없으면 먼저 보낸 응답이 늦게 도착해 **방금 읽은 값을 덮는다.**
  ///   더 나쁜 경우는 계정이 바뀐 뒤다 — uid 를 await 이전에 잡아 두므로
  ///   이전 사용자의 지원·근태가 새 사용자의 홈에 앉을 수 있다.
  ///   그래서 **가장 마지막에 시작한 호출만**, 그리고 **그 사이 uid 가 바뀌지
  ///   않았을 때만** state 를 쓴다.
  int _homeLoadSeq = 0;

  Future<void> _loadHomeData() async {
    if (_isLoadingHomeData) {
      return; // 동시 실행 방어
    }
    final uid = context.read<UserProvider>().currentUser?.uid;
    // 추천 점수 계산에 사용 — await 이전에 동기 캡처 (갱신 주기와 무관하게 안전)
    final user = context.read<UserProvider>().currentUser;
    if (uid == null || !mounted) {
      return;
    }
    final seq = ++_homeLoadSeq;
    bool superseded() {
      if (seq != _homeLoadSeq) return true;
      // 계정이 바뀌었으면 이 응답은 다른 사람의 것이다.
      return context.read<UserProvider>().currentUser?.uid != uid;
    }
    _isLoadingHomeData = true;
    setState(() {
      _isLoadingData = true;
      // [PERF-P1] 다른 계정의 마지막 성공 값을 '재조회 중 유지'로 보이지 않는다.
      if (_mainRoundUid != null && _mainRoundUid != uid) {
        _mainRoundDone = false;
        _idRequestsFailed = false;
        _renewalProposalsFailed = false;
      }
    });
    // [R7-P4.4E.8A] 새로고침마다 슬롯을 다시 본다 — 정원·마감이 바뀐다.
    //   읽기 수는 "내가 활성 지원을 가진 flex 공고 수"(보통 0~2)이고
    //   후보 공고 수와 무관하다.
    _slotFetchAttempted.clear();
    final now = _now();
    try {
      // [PREDEVICE-CONTRACT-CONTEXT] 미서명 계약 목록도 홈 로드에 합류시킨다.
      //   지금까지는 로그인 시점과 FCM 수신 시에만 갱신됐다. push를 놓치면
      //   앱을 다시 켤 때까지 계약 배너가 나타나지 않았고, 배너를 읽는
      //   일정 카드·출근 카드도 같이 낡은 상태로 남았다.
      //   실패해도 홈 로드를 깨뜨리지 않는다 — 배너는 부가 정보다.
      unawaited(context
          .read<UserProvider>()
          .refreshPendingContracts(joinInFlight: true) // 로그인 직후 같은 조회가 날아가 있으면 합류
          .catchError((Object e) => debugPrint('⚠️ 미서명 계약 갱신 실패: $e')));

      // [PREDEVICE-WORKER-ERROR-NOT-ZERO] 도메인별로 실패를 따로 받는다.
      //   Future.wait는 하나가 실패하면 나머지가 성공했어도 결과를 통째로
      //   버린다. 지원 내역만 못 불러왔을 뿐인데 오늘 근무·추천 공고·신분증
      //   요청까지 같이 사라지면, 화면 전체가 빈 것처럼 보인다.
      //   실패한 칸만 모른다고 두고 나머지는 그대로 그린다.
      Object? appsErr;
      Object? attsErr;
      Object? tosErr;
      Object? idErr;
      Object? tailErr;
      Object? contractsErr;
      // [R7-P2-1 최종] 월별 원장의 연·월도 **KST 달력월**이다 — 서버가 그
      //   자로 자른다(`getMyMonthlyAttendances`).
      final kstNow = FormatHelper.toKstDate(now);
      // [R7-P2-1 잔여] 어제가 지난달인 날(=1일)에만 꼬리를 함께 읽는다.
      //   기준은 **KST 달력일**이다 — 기기 로컬 1일로 재면 비-KST 기기에서
      //   하루 어긋나 정작 필요한 날 꼬리를 안 읽거나 필요 없는 날 읽는다.
      final needsTail = kstNow.day == 1;
      final prevMonthDay =
          DateTime.utc(kstNow.year, kstNow.month, 0); // 지난달 말일(KST)
      // [PII-DOC-R1.6.1] 보완 요청은 홈의 숫자를 만들지 않으므로 별도로
      //   가져오고, 실패해도 다른 영역을 오류 상태로 만들지 않는다.
      //   단 실패를 "할 일 없음"으로 바꾸지는 않는다 — 카드를 숨길 뿐이다.
      // [PERF-P1 H] 보완·연장은 1라운드 결과를 쓰지 않는다 — 1라운드와 **같이** 출발시켜 구역이 한 번에 정해질
      //   가능성을 높인다(호출 수 변화 0 · 순서만). 같은 `superseded()` 가드로 늦은 응답을 버린다.
      unawaited(_reads.documentCorrections().then((s) {
        if (!mounted || superseded()) return;
        _zoneSetState(() {
          _correctionSurface = s;
          _correctionsLoaded = true;
        });
      }, onError: (Object e) {
        // 운영 읽기(loadMine)는 스스로 failed 를 돌려준다. 그래도 던지면 같은 '확인 못 함' 카드로 — 영원히 LOADING 에 두지 않는다.
        debugPrint('⚠️ 보완 요청 조회 실패: $e');
        if (!mounted || superseded()) return;
        _zoneSetState(() {
          _correctionSurface = DocumentCorrectionSurface.failed;
          _correctionsLoaded = true;
        });
      }));

      // [RENEWAL-PROPOSAL-COMMITMENT] 연장 제안은 **근로자가 할 일**이다.
      //
      //   관리자가 제안을 보내면 근로자가 수락하거나 거절해야 새 기간이
      //   정해진다. 알림을 읽거나 지워도 그 일은 사라지지 않는다 —
      //   출처는 알림이 아니라 제안 문서다.
      //
      //   실패를 "제안 없음"으로 바꾸지 않는다: 못 읽었으면 카드를
      //   숨기고 다음 조회를 기다린다. 없는 할 일을 지어내지도 않는다.
      //   [판정290 D290-01] 실패는 일반 한 줄이 말한다(카드 숨김은 그대로).
      unawaited(_reads.myRenewalProposals().then((list) {
        if (!mounted || superseded()) return;
        final now = _now();
        _zoneSetState(() {
          _renewalProposals =
              list.where((p) => p.isActionableAt(now)).toList();
          _renewalProposalsLoaded = true;
          _renewalProposalsFailed = false;
        });
      }).catchError((Object e) {
        debugPrint('⚠️ [연장제안] 홈 조회 실패: $e');
        if (!mounted || superseded()) return;
        _zoneSetState(() => _renewalProposalsFailed = true);
      }));

      // [PERF-L9 · impl_15] 묶음 경로 — 같은 6 섹션을 한 번에(실패 섹션 의미는 아래 개별 경로와 같다).
      final bundleFn = _reads.homeBundle;
      final List<Object?> results;
      if (bundleFn != null) {
        final includeLegal = _bundleLegal != null && !_bundleLegal!.isCompleted;
        final WorkerHomeBundle b;
        try {
          b = await bundleFn(
            uid: uid,
            generation: '$uid#$seq',
            months: [
              (year: kstNow.year, month: kstNow.month),
              if (needsTail) (year: prevMonthDay.year, month: prevMonthDay.month),
            ],
            includeLegal: includeLegal,
          );
        } catch (e) {
          // 묶음 클라이언트는 섹션별로 돌려주며 던지지 않는다 — 던졌다면 예상 밖(전부 실패로 본다 · 약관은 원래 경로).
          if (includeLegal) _resolveBundleLegal(null);
          rethrow;
        }
        if (includeLegal) _resolveBundleLegal(b.legalReadiness);
        T v<T>(HomeBundleOutcome<T> o, T empty) => o.ok ? o.value as T : empty;
        appsErr = b.applications.error;
        final cur = b.monthlyAttendances[WorkerHomeBundle.monthKey(kstNow.year, kstNow.month)] ??
            HomeBundleOutcome<List<AttendanceModel>>.fail(StateError('month missing'));
        attsErr = cur.error;
        tosErr = b.publishedTOs.error;
        idErr = b.idCardRequests.error;
        HomeBundleOutcome<List<AttendanceModel>>? tail;
        if (needsTail) {
          tail = b.monthlyAttendances[WorkerHomeBundle.monthKey(prevMonthDay.year, prevMonthDay.month)] ??
              HomeBundleOutcome<List<AttendanceModel>>.fail(StateError('month missing'));
          tailErr = tail.error;
        }
        contractsErr = b.contracts.error;
        results = [
          v(b.applications, <ApplicationModel>[]),
          v(cur, <AttendanceModel>[]),
          v(b.publishedTOs, <TOModel>[]),
          v(b.idCardRequests, <IdCardAccessRequestModel>[]),
          tail == null ? const <AttendanceModel>[] : v(tail, <AttendanceModel>[]),
          v(b.contracts, <EmploymentContractModel>[]),
        ];
      } else {
      results = await Future.wait([
        _reads.myApplications(uid).catchError((Object e) {
          appsErr = e;
          return <ApplicationModel>[];
        }),
        _reads
            .myMonthlyAttendances(
                userId: uid, year: kstNow.year, month: kstNow.month)
            .catchError((Object e) {
          attsErr = e;
          return <AttendanceModel>[];
        }),
        _reads.publishedTOs().catchError((Object e) {
          tosErr = e;
          return <TOModel>[];
        }),
        // [DS-03] 홈 요청 진입점 — 기존 홈 로드 1회에 합류시킨다 (중복 호출 없음)
        _reads.pendingIdCardRequests(uid).catchError((Object e) {
          idErr = e;
          return <IdCardAccessRequestModel>[];
        }),
        if (needsTail)
          _reads
              .myMonthlyAttendances(
                  userId: uid,
                  year: prevMonthDay.year,
                  month: prevMonthDay.month)
              .catchError((Object e) {
            tailErr = e;
            return <AttendanceModel>[];
          })
        else
          Future<List<AttendanceModel>>.value(const <AttendanceModel>[]),
        // [CONTRACT-DISPATCH-B4] 오늘 근무 CTA 의 계약 판정 근거(출퇴근 화면과 같은 읽기)
        _reads.myContracts(uid).catchError((Object e) {
          contractsErr = e;
          return <EmploymentContractModel>[];
        }),
      ]);
      }
      if (!mounted || superseded()) return;

      // 지원 내역이 실패했으면 이전 값을 유지한다 — 0으로 덮어쓰지 않는다.
      if (appsErr == null) {
        _applications = results[0] as List<ApplicationModel>;
      } else {
        debugPrint('⚠️ 지원 내역 로드 실패: $appsErr');
      }
      if (attsErr == null) {
        _attendances = results[1] as List<AttendanceModel>;
        _attendancesFailed = false;
      } else {
        debugPrint('⚠️ 이번 달 근태 로드 실패: $attsErr');
        _attendancesFailed = true;
      }
      // [R8-P7.4] 실패했으면 이전 값을 유지하고, 비어 있는 이유를 기록해 둔다.
      if (tosErr == null) {
        _publishedTos = results[2] as List<TOModel>;
        _postingsFailed = false;
      } else {
        debugPrint('⚠️ 공개 공고 로드 실패: $tosErr');
        _postingsFailed = _publishedTos.isEmpty;
      }
      if (idErr == null) {
        _idRequestSurface =
            PendingIdRequestSurface.from(results[3] as List<IdCardAccessRequestModel>);
        _idRequestsLoaded = true;
        _idRequestsFailed = false;
      } else {
        // [판정290 D290-01] ERROR 는 terminal 이지만 정상 0 이 아니다 — loaded 를 세우지 않고 실패만 적는다.
        debugPrint('⚠️ 신분증 요청 조회 실패: $idErr');
        _idRequestsFailed = true;
      }
      if (tailErr == null) {
        _prevMonthTail = results[4] as List<AttendanceModel>;
      } else {
        debugPrint('⚠️ 지난달 근태 꼬리 로드 실패: $tailErr');
        _prevMonthTail = const [];
      }
      // 어느 쪽이든 못 읽었으면 어제의 퇴근 여부를 말할 수 없다.
      _overnightUnknown = attsErr != null || tailErr != null;
      // 못 읽었으면 null(=모름) — 이전 값으로 동의를 추정하지 않는다.
      if (contractsErr != null) debugPrint('⚠️ 홈 계약 조회 실패: $contractsErr');
      _contracts = contractsErr == null
          ? results[5] as List<EmploymentContractModel>
          : null;
      _rebuildCaches();

      // [R7-P4.4E.8A] 관계가 있는 flex 공고의 슬롯만 뒤이어 읽는다.
      //   1차 계산은 슬롯 없이도 **거짓 0 을 만들지 않는다**(모르면 남긴다).
      //   슬롯이 오면 그 날짜만 정확해진다. 읽기 수는 "내가 지원한 공고 수"
      //   이고 후보 공고 수와 무관하다.
      unawaited(_loadRelationSlots(superseded));

      // 지원 내역은 홈의 숫자를 만드는 축이다 — 그것만 오류 상태로 올린다.
      if (appsErr != null) {
        _zoneSetState(() {
          _isLoadingData = false;
          _homeLoadFailed = true;
          _mainRoundDone = true;
          _mainRoundUid = uid;
        });
        _toastAfterTour('지원 현황을 불러오지 못했어요.');
        return;
      }

      // [WORKER-HOME-CRITICAL-PATH] 홈의 숫자·일정·추천 목록은 위 1라운드로 이미 정해졌다.
      //   아래 사업장 문서는 추천 카드 **이미지**(mainImageUrl)에만 쓰인다 — 그것 때문에
      //   지원·근태·수입까지 스켈레톤으로 붙잡아 두지 않는다(LOCAL 추적: 주요 정보가
      //   1라운드 + 사업장 문서 왕복을 다 기다렸다). 값은 모두 이번 회차의 새 응답이다.
      _zoneSetState(() {
        _isLoadingData = false;
        _homeLoadFailed = false;
        _mainRoundDone = true;
        _mainRoundUid = uid;
      });

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
        targetBizIds =
            _publishedTos.map((t) => t.businessId).toSet().take(8).toList();
      }
      if (targetBizIds.isNotEmpty) {
        final bizResults = await Future.wait(
          targetBizIds.map((id) => _reads.businessById(id)),
        );
        if (!mounted || superseded()) return;
        final cache = <String, BusinessModel>{};
        for (var i = 0; i < targetBizIds.length; i++) {
          final biz = bizResults[i];
          if (biz != null) cache[targetBizIds[i]] = biz;
        }
        // [PERF-P6] 보이는 두 장의 사진 받기를 카드가 그려지기 전에 출발시킨다(기다리지 않음).
        if (user != null) _precacheRecommendImages(user, cache);
        setState(() => _businessCache = cache);
      }
      // [impl_12 · P2] 이번 진입의 **완전한 성공**만 저장한다 — 공고·지원 조회 성공 · 지원 200 상한(일부) 아님 · 날짜 미선택.
      //   0장이면 옛 추천을 지운다(0장 스냅샷 저장 0). 같은 회차·같은 계정일 때만.
      if (user != null && !superseded()) {
        _saveRecommendCache(user,
            complete: tosErr == null && !_postingsFailed && !_applicationsMaybePartial && _selectedDateChip == null);
      }
    } catch (e) {
      debugPrint('❌ 홈 데이터 로드 실패: $e');
      if (mounted) {
        // 실패를 화면 상태로 남긴다 — 토스트는 사라지고 숫자는 남는다.
        _zoneSetState(() {
          _isLoadingData = false;
          _homeLoadFailed = true;
          if (!superseded()) {
            _mainRoundDone = true;
            _mainRoundUid = uid;
          }
        });
        _toastAfterTour('홈 정보를 불러오지 못했어요. 다시 시도해 주세요');
      }
    } finally {
      _isLoadingHomeData = false;
    }
  }

  // ── [PERF-P1 · 판정289 §4 · 판정290] 구역 조정 · 일반 실패 행 · 위쪽 변화 보정 ─────────────────

  bool get _legalTerminal =>
      _legalReadiness != null && _legalReadiness!.status != LegalReadinessStatus.loading;
  bool get _renewalTerminal => _renewalProposalsLoaded || _renewalProposalsFailed;

  /// 모든 필수 출처가 terminal 인가(새 읽기 0 · 기존 필드에서 계산). ERROR 도 terminal 이다(≠ 정상 0).
  bool get _allRequiredTerminal =>
      _mainRoundDone && _seenIdsLoaded && _correctionsLoaded && _renewalTerminal && _legalTerminal;

  /// 약속 자리가 구역 '확인 중' 뼈대인가.
  bool get _promisePlaceholder =>
      !_zoneRevealed || !_mainRoundDone || (!_seenIdsLoaded && _heroTodayApp == null);

  /// 긴급 행동이 확정됐다 — 자정 퇴근(필요/모름) · 계약해지 응답(요청/모름) · 오늘 약속.
  bool get _urgentConfirmed {
    if (!_mainRoundDone) return false;
    if (_overnightUnknown || _openOvernightAttendance() != null) return true;
    if (_heroTodayApp != null) return true;
    final term = PendingTerminationSurface.from(_applications, available: !_homeLoadFailed);
    return term.isVisible || term.isUnavailable;
  }

  void _updateReveal() {
    if (_zoneRevealed) return;
    if (_revealCapPassed || _allRequiredTerminal || _urgentConfirmed) {
      _zoneRevealed = true;
      _revealTimer?.cancel();
    }
  }

  /// 구역에 영향을 주는 상태 변경은 모두 여기로 — (1) 바뀌기 **전** 기하로 보정 조건을 잡고 (2) 첫 표시 판정을 같이 한다.
  void _zoneSetState(VoidCallback fn) {
    if (!mounted) return;
    _captureZoneAnchor();
    setState(() {
      fn();
      _updateReveal();
    });
  }

  void _onLegalReadiness(LegalReadiness r) {
    if (!mounted) return;
    _zoneSetState(() => _legalReadiness = r);
  }

  /// [판정290 D290-01] 실패한 출처만 실제로 다시 읽는다. 진행 중이면 겹쳐 부르지 않는다(홈 재조회 중에도 행은 잠긴다).
  ///   같은 uid · 같은 홈 회차의 응답만 반영한다 — 그 사이 새 홈 조회가 출발했거나 계정이 바뀌면 버린다.
  ///   성공(정상 0 포함)만 실패를 지운다. 이미 읽어 둔 성공 카드는 건드리지 않는다.
  Future<void> _retryFailedSources() async {
    if (_retryingFailedSources || _isLoadingHomeData) return;
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) return;
    final seq = _homeLoadSeq;
    bool stale() => !mounted || seq != _homeLoadSeq || context.read<UserProvider>().currentUser?.uid != uid;
    final wantId = _idRequestsFailed;
    final wantRenewal = _renewalProposalsFailed;
    if (!wantId && !wantRenewal) return;
    _zoneSetState(() => _retryingFailedSources = true);
    try {
      await Future.wait<void>([
        if (wantId)
          _reads.pendingIdCardRequests(uid).then((reqs) {
            if (stale()) return;
            _zoneSetState(() {
              _idRequestSurface = PendingIdRequestSurface.from(reqs);
              _idRequestsLoaded = true;
              _idRequestsFailed = false;
            });
          }, onError: (Object e) => debugPrint('⚠️ 신분증 요청 다시 확인 실패: $e')),
        if (wantRenewal)
          _reads.myRenewalProposals().then((list) {
            if (stale()) return;
            final now = _now();
            _zoneSetState(() {
              _renewalProposals = list.where((p) => p.isActionableAt(now)).toList();
              _renewalProposalsLoaded = true;
              _renewalProposalsFailed = false;
            });
          }, onError: (Object e) => debugPrint('⚠️ 연장 제안 다시 확인 실패: $e')),
      ]);
    } finally {
      if (mounted) _zoneSetState(() => _retryingFailedSources = false);
    }
  }

  /// 구역 하단·약속 앞의 상태 줄 — '확인 중'(약속 자리 뼈대가 아닐 때만) · '확인 실패'(신분증·연장 현재 ERROR).
  ///   출처·사업장·건수·요청 존재를 말하지 않는다. 퇴근·해지·보완은 자기 실패 카드가 말하므로 여기서 다시 말하지 않는다.
  Widget _buildRequiredStatusRows(BuildContext context, double s) {
    if (!_zoneRevealed) return const SizedBox.shrink();
    final rows = <Widget>[];
    final infoStyle = ConceptText.body(color: AppColors.textSecondary);
    if (!_promisePlaceholder && !_allRequiredTerminal) {
      rows.add(Semantics(
        key: const ValueKey('worker-home-required-pending'),
        container: true,
        label: '일부 정보를 확인하고 있어요',
        excludeSemantics: true,
        // 움직이지 않는 표지 — 출처 하나가 오래 걸려도 끝없는 애니메이션(매 프레임 다시 그리기)을 만들지 않는다.
        child: Row(children: [
          Icon(Icons.hourglass_empty_rounded, size: 16 * s, color: AppColors.textSecondary),
          SizedBox(width: 10 * s),
          Expanded(child: Text(TextLayout.keepWords('일부 정보를 확인하고 있어요'), style: infoStyle)),
        ]),
      ));
    }
    if (_idRequestsFailed || _renewalProposalsFailed) {
      final busy = _retryingFailedSources || _isLoadingData;
      if (rows.isNotEmpty) rows.add(SizedBox(height: 8 * s));
      rows.add(Semantics(
        key: const ValueKey('worker-home-required-error'),
        container: true,
        button: true,
        enabled: !busy,
        label: busy ? '일부 정보를 다시 확인하고 있어요' : '일부 정보를 확인하지 못했어요 · 다시 시도',
        onTap: busy ? null : _retryFailedSources,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: busy ? null : _retryFailedSources,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(children: [
              Icon(Icons.cloud_off_outlined, size: 20 * s, color: AppColors.textSecondary),
              SizedBox(width: 10 * s),
              Expanded(
                child: Text(
                  TextLayout.keepWords('일부 정보를 확인하지 못했어요'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
              ),
              SizedBox(width: 8 * s),
              if (busy)
                Icon(Icons.hourglass_empty_rounded, size: 16 * s, color: AppColors.textSecondary)
              else
                const Text('다시 시도',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brand)),
            ]),
          ),
        ),
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows),
    );
  }

  bool _onHomeScrollNotification(ScrollNotification n) {
    if (n.depth != 0 || _selfCorrecting) return false;
    if (n is ScrollStartNotification) {
      _userScrolling = true;
      _inputEpoch++;
    } else if (n is UserScrollNotification) {
      if (n.direction != ScrollDirection.idle) {
        _userScrolling = true;
        _inputEpoch++;
      }
    } else if (n is ScrollEndNotification) {
      _userScrolling = false;
    }
    return false;
  }

  /// 표지([_zoneEndKey]) 또는 기준 블록([_anchorKey])의 **내용 좌표**(스크롤 0 기준 y). 없거나 아직 배치 전이면 null.
  double? _contentY(GlobalKey key) {
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(ro);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(ro, 0.0).offset;
  }

  bool get _homeScrollIdle {
    if (!_homeScroll.hasClients) return false;
    final pos = _homeScroll.position;
    return _pointersDown == 0 && !_userScrolling && !pos.isScrollingNotifier.value;
  }

  /// 바뀌기 전 기하로 보정 조건을 잡는다 — 프레임당 1회(같은 프레임의 여러 변경은 다음 프레임 한 번의 순변화로 묶는다).
  void _captureZoneAnchor() {
    if (_zoneAnchor != null) return;
    if (!_homeScroll.hasClients) return;
    final pos = _homeScroll.position;
    if (!pos.hasContentDimensions || !pos.hasPixels) return;
    if (pos.pixels <= 0) return; // 최상단 — 자연 삽입
    if (!_homeScrollIdle) return; // 끌기·관성·hold·프로그램 스크롤 중 보정 0
    final endY = _contentY(_zoneEndKey);
    if (endY == null || endY > pos.pixels) return; // 구역 일부라도 보이면 자연 삽입
    final anchorY = _contentY(_anchorKey);
    if (anchorY == null) return;
    final anchor = _ZoneAnchor(
      position: pos,
      pixels: pos.pixels,
      viewport: pos.viewportDimension,
      endY: anchorY,
      epoch: _inputEpoch,
      seq: _homeLoadSeq,
      uid: context.read<UserProvider>().currentUser?.uid,
    );
    _zoneAnchor = anchor;
    UserHomeScreen._stat('scheduled');
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyZoneAnchor(anchor));
  }

  /// 실행 직전 재검사 — 하나라도 달라졌으면 버린다(조작 뒤 누적 보정 0 · 자기 보정 재귀 0).
  void _applyZoneAnchor(_ZoneAnchor a) {
    if (!identical(_zoneAnchor, a)) return;
    _zoneAnchor = null;
    void discard() => UserHomeScreen._stat('discarded');
    if (!mounted) return discard();
    if (a.seq != _homeLoadSeq || a.uid != context.read<UserProvider>().currentUser?.uid) return discard();
    if (!_homeScroll.hasClients || !identical(_homeScroll.position, a.position)) return discard();
    final pos = _homeScroll.position;
    if (!pos.hasContentDimensions || !pos.hasPixels) return discard();
    if (_inputEpoch != a.epoch || !_homeScrollIdle) return discard();
    if ((pos.viewportDimension - a.viewport).abs() > 0.5) return discard();
    final anchorY = _contentY(_anchorKey);
    if (anchorY == null) return discard();
    final delta = anchorY - a.endY; // 카드·간격·확인 중/실패 행의 삽입·제거를 모두 담은 실제 순변화(기준 블록의 이동)
    final target = (a.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble();
    if (delta.abs() <= 0.5 || (target - pos.pixels).abs() <= 0.5) {
      UserHomeScreen._stat('noop');
      return;
    }
    _selfCorrecting = true;
    try {
      pos.jumpTo(target);
      UserHomeScreen._stat('applied');
    } finally {
      _selfCorrecting = false;
    }
  }

  // ── [DS-03] 요청 처리 후 진입점만 갱신 ─────────────────────────
  /// 홈 전체를 다시 불러오지 않는다 — 바뀐 것은 요청 목록뿐이다.
  ///
  /// [PREDEVICE-WORKER-ERROR-NOT-ZERO] 조회가 실패하면 진입점을 지우지 않고
  /// 직전 상태를 그대로 둔다. 예전에는 서비스가 빈 목록을 돌려줘 카드가 조용히
  /// 사라졌는데, 그러면 아직 남아 있는 요청을 근로자가 볼 방법이 없어진다.
  Future<void> _reloadPendingIdRequests() async {
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) return;
    try {
      final reqs = await _reads.pendingIdCardRequests(uid);
      if (!mounted) return;
      _zoneSetState(() {
        _idRequestSurface = PendingIdRequestSurface.from(reqs);
        _idRequestsLoaded = true;
        _idRequestsFailed = false;
      });
    } catch (e) {
      debugPrint('❌ 신분증 요청 갱신 실패: $e');
      if (mounted) ToastHelper.showError('요청 목록을 새로 불러오지 못했어요');
    }
  }

  /// 홈 → 기존 요청 다이얼로그. 닫힌 뒤 남은 건수를 다시 조회한다.
  /// 마지막 1건까지 처리하면 홈 진입점이 즉시 사라진다.
  Future<void> _openMyRequests(String uid) async {
    await MyRequestsDialog.show(context, applicantUid: uid);
    if (!mounted) return;
    await _reloadPendingIdRequests();
  }

  // ── 반응형 스케일: 화면 너비 기준 ──────────────────────────────
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
                      _reads.invalidatePublishedTOsCache();
                      return _loadHomeData();
                    },
                    // [판정290 D290-02] 손가락 접촉·끌기/관성·프로그램 스크롤을 각각 본다(하나의 notifier 로 대신하지 않는다).
                    child: Listener(
                      onPointerDown: (_) {
                        _pointersDown++;
                        _inputEpoch++;
                      },
                      onPointerUp: (_) {
                        if (_pointersDown > 0) _pointersDown--;
                      },
                      onPointerCancel: (_) {
                        if (_pointersDown > 0) _pointersDown--;
                      },
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onHomeScrollNotification,
                        child: SingleChildScrollView(
                          controller: _homeScroll,
                          physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics()),
                          child: _buildUserBody(context, s, up),
                        ),
                      ),
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
      color: AppColors.warningBg, // 주황색 경고 배경 (AppColors.warningBg 유사)
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.verified_user_outlined,
                color: AppColors.warningDark, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '지원을 위해 본인인증이 필요해요',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.warningDark,
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
                      fontSize: 14,
                      color: AppColors.brand,
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
      // [DU306 Standards §12.1] 머리 관계 — 왼쪽은 본문과 같은 gutter(<360:16 / 그 밖 20), 아래 0. 행동행(알림 48, 역할 전환이
      //   다음 줄이면 그 줄까지) → 계정 메타 합계 8 은 본문 첫 블록의 위 여백 [_kHeaderToMeta] 하나가 맡는다(중복 없음).
      //   [DU306 L2] 위 8 → 0(배율 s 를 곱하지 않는다). 로고 잉크 top = 머리 시작 + (행 높이 − 28)/2 + 2 — 배너 숨김·행 48 이면
      //   SafeArea top + 12. 오른쪽 12*s·로고(잉크 24/slot 84×28)·알림 48 receiver·역할 전환 배치 규칙은 그대로다.
      padding: EdgeInsets.fromLTRB(_gutter(context), 0, 12 * s, 0),
      // [DU1 구현69 VQ-01] 시안은 헤더와 본문을 선이 아니라 여백으로 나눈다 — 아래 구분선 제거
      decoration: const BoxDecoration(color: Colors.white),
      // [CP01] 로고 = 공용 글자 로고(고정 그림, 정본 DU_concept_precise_spec_audit §3). 원형 앱 아이콘 장식은 뺀다.
      //   SubAdmin 역할 전환이 로고·알림과 한 줄에 다 들어가지 않는 폭·글자 배율이면 다음 줄 오른쪽으로 내린다
      //   (글자를 줄이지 않는다). 필요한 폭은 실제 글자 배율·번들 글꼴로 잰다.
      child: LayoutBuilder(builder: (context, c) {
        // 알림 버튼
        // [DU306 L2] 머리 위 여백 0 → 배지 위 끝도 버튼 위(0)에 둔다(기본 −4 는 SafeArea 위로 4 돌출).
        final bell = NotificationBadge(
          badgeTop: 0,
          child: _headerIconBtn(
              context, s, Icons.notifications_outlined, '알림',
              () => Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => const NotificationScreen()))),
        );
        // 내 정보 버튼 제거 — 하단 MY 탭이 공식 진입점으로 통일됨
        if (!up.isSubAdmin) {
          return Row(children: [const AlfitWordmark(), const Spacer(), bell]);
        }
        // SubAdmin 모드 토글 (서브어드민 전용) — 구현 계획서 주의사항
        final toggle = _buildModeToggle(context, s, up);
        final need = AlfitWordmark.slotWidth + 8 * s + _modeToggleWidth(context, s) + 8 * s + 48;
        if (c.maxWidth >= need) {
          return Row(children: [
            const AlfitWordmark(),
            const Spacer(),
            toggle,
            SizedBox(width: 8 * s),
            bell,
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [const AlfitWordmark(), const Spacer(), bell]),
          Align(alignment: Alignment.centerRight, child: toggle),
        ]);
      }),
    );
  }

  /// 흰 헤더용 아이콘 버튼 (dark icon on white bg)
  /// [CP01] 누름 영역 최소 48×48 — 보이는 아이콘(22*s)·여백은 그대로 두고 영역만 넓힌다(이전 38*s).
  Widget _headerIconBtn(BuildContext context, double s, IconData icon,
      String label, VoidCallback onTap) {
    return Semantics(
      label: label,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Padding(
              padding: EdgeInsets.all(8 * s),
              child: Icon(icon, color: AppColors.textSecondary, size: 22 * s),
            ),
          ),
        ),
      ),
    );
  }

  // ── 모드 토글 (서브어드민 전용) — 흰 배경용 색상 ──────────────
  // [CP01] 선택지마다 누름 영역 48×48 이상(이전 글자 높이+8*s ≈ 24). 보이는 모양은 그대로 —
  //   테두리 띠는 선택 알약+위아래 3dp 를 감싸고, 남는 높이는 띠 바깥의 투명한 누름 영역이다.
  //   선택 색은 예전 파랑(infoDark) → 브랜드(brand): 같은 머리의 글자 로고와 한 색.
  Widget _buildModeToggle(BuildContext context, double s, UserProvider up) {
    final isAdmin = up.isAdminMode;
    final pillH = _modeTogglePillHeight(context, s);
    final optH = pillH + 6 > 48 ? pillH + 6 : 48.0;
    final inset = (optH - (pillH + 6)) / 2;
    return Stack(children: [
      Positioned.fill(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: inset),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderLight),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _toggleOpt(context, s, label: '지원자', selected: !isAdmin, height: optH,
              onTap: () { if (isAdmin) up.toggleAdminMode(); }),
          _toggleOpt(context, s, label: '관리자', selected: isAdmin, height: optH,
              onTap: () { if (!isAdmin) _switchToAdminMode(context, up); }),
        ]),
      ),
    ]);
  }

  /// [CP01] 역할 전환 글자 한 줄을 실제 글자 배율·번들 글꼴로 잰다(굵게 = 넓은 쪽).
  TextPainter _modeToggleLabel(BuildContext context, String label) => TextPainter(
        text: TextSpan(
            text: label,
            style: DefaultTextStyle.of(context).style.merge(
                const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();

  /// [CP01] 선택 알약 높이 = 글자 줄 높이 + 위아래 4*s.
  double _modeTogglePillHeight(BuildContext context, double s) {
    final tp = _modeToggleLabel(context, '지원자');
    final h = tp.height + 8 * s;
    tp.dispose();
    return h;
  }

  /// [CP01] 역할 전환 토글 전체 폭 — 선택지 = 글자 + 좌우 10*s(최소 48), 바깥 좌우 3.
  double _modeToggleWidth(BuildContext context, double s) {
    double opt(String label) {
      final tp = _modeToggleLabel(context, label);
      final w = tp.width + 20 * s;
      tp.dispose();
      return w < 48 ? 48 : w;
    }
    return opt('지원자') + opt('관리자') + 6;
  }

  Widget _toggleOpt(BuildContext context, double s,
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
              color: selected ? AppColors.brand : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              style: TextStyle(
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

  // ─────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────
  // 지원자 바디 — 시안 섹션 순서 그대로
  // ─────────────────────────────────────────────────────────────
  Widget _buildUserBody(BuildContext context, double s, UserProvider up) {
    final theme = Theme.of(context);
    // [CP03] 순서·리듬 = 구성 확정 Q2·Q9(requests/DU_concept_CP03_composition_decision_2026-11-11.md).
    //   보이는(높이>0) 블록 사이에만 간격을 둔다 — 같은 수준 카드끼리 12, 그 밖 24. 숨은 카드는 간격도 남기지 않는다.
    //   각 블록의 표시 조건·목적지·복귀 갱신은 그대로다(순서만 바뀐다).
    return Padding(
      padding: const EdgeInsets.only(bottom: ConceptSpace.sectionGap),
      child: _RhythmColumn(children: [
        // [판정285 §2 · 대표 지시 2026-11-26] 순서 = 머리(인사·KST 날짜) → 독립 필수응답 → 실제 약속(B>A) →
        //   필요한 시작 준비 → 통합 날짜 영역(띠·선택일 내 일정·그날 일자리) → 지원 현황 → 초대 → 추천 2 → 수입 → 근무 기록.
        //   날짜띠는 머리 바로 아래(CP03 Q2)에서 내려왔다 — 응답 기한·출퇴근이 탐색보다 먼저 온다.
        //   `이번 주 일정` 섹션은 지웠다(같은 7칸 줄이 두 번 · 과거/전체는 하단 내 일정 탭).
        // ① 계정 이름 · 큰 머리 · KST 날짜
        _RhythmSlot(kind: _Rhythm.block, child: _buildGreeting(context, s, up)),
        // ② 독립 필수응답 — 약속보다 앞(Q2). 각자 표시 조건으로 스스로 숨는다.
        // [R7-P2-1 잔여] 자정을 넘긴 근무의 **퇴근**은 이미 시작된 일이다 — 응답하지 않으면
        //   `missed_checkout` 으로 자동 처리돼 임금이 다퉈진다. 오늘 약속이 함께 있으면 **둘 다** 보인다.
        _RhythmSlot(kind: _Rhythm.card, child: _buildOvernightCheckoutCard(context, s)),
        // [DS-03] 신분증 열람 요청 — 상대방이 기다리는 요청. Hero 우선순위 계산에 참여하지 않는다.
        _RhythmSlot(kind: _Rhythm.card, child: _buildIdRequestCard(context, s, up)),
        // 계약해지 응답 — 신분증 요청과 **별도** 표면(의미가 다르다)
        _RhythmSlot(kind: _Rhythm.card, child: _buildTerminationRequestCard(context, s, up)),
        // [RENEWAL-PROPOSAL-COMMITMENT] 연장 제안 — 사업장이 대답을 기다린다.
        _RhythmSlot(kind: _Rhythm.card, child: _buildRenewalProposalCard(context, s)),
        // [PII-DOC-R1.6.1] 서류 보완 할 일 — 이미 일한 급여가 막혀 있을 수 있다.
        _RhythmSlot(kind: _Rhythm.card, child: _buildCorrectionTaskCard(context, s)),
        // [R7-LEGAL.1B.1] 약관 재동의 — 해당 없으면 스스로 사라진다(공용 카드, 안쪽 여백은 범위 밖).
        // [PERF-P1] 첫 표시 전에도 마운트는 유지한다(자기 조회·복귀 갱신 그대로) — 보이지만 않게(높이 0 · 간격 0).
        _RhythmSlot(
            kind: _Rhythm.card,
            child: Offstage(
                offstage: !_zoneRevealed,
                child: LegalTaskCard(
                    scale: s,
                    loadReadiness: _reads.homeBundle != null ? _legalLoader : _reads.legalReadiness,
                    onReadiness: _onLegalReadiness))),
        // [PERF-P1 · 판정290 D290-01] 구역 하단·약속 앞 — '확인 중'(끝나지 않은 출처) · '확인 실패'(신분증·연장) 각 최대 1행.
        _RhythmSlot(kind: _Rhythm.card, child: _buildRequiredStatusRows(context, s)),
        // ③ 실제 약속 — B(오늘) > A(새 확정). 로딩 중 skeleton. [판정285 §2] 정상 0 의 큰 카드는 없앴다 —
        //   그 사실은 통합 날짜 영역의 짧은 안내가 말한다(지원 조회 실패·로딩은 0 으로 말하지 않는다).
        _RhythmSlot(kind: _Rhythm.section, child: _buildPriorityCard(context, s, theme)),
        // [판정290 D290-02] 구역 아래끝 표지(높이 0 · 간격 0) — 위쪽 변화의 실제 순높이를 이 표지의 이동으로 잰다.
        _RhythmSlot(kind: _Rhythm.card, child: SizedBox(key: _zoneEndKey, height: 0)),
        // ④ [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 대표 결정 2026-11-25 · 판정285 §2-4] 「시작 준비」(지역 · 신분 · 급여) —
        //   실제 약속 바로 뒤 한 자리(약속이 없으면 필수응답 바로 뒤). 자기 준비 안내다(필수응답으로 재분류하지 않는다).
        _RhythmSlot(kind: _Rhythm.card, child: _buildReadinessCard(context, s, up)),
        // ⑤ 통합 날짜 영역 — 내 일정만: 띠(확정/지원 중 두 점) → 범례·날짜 해제/선택 → 오늘 정상0 안내 | 선택일 내 일정.
        _RhythmSlot(kind: _Rhythm.section, child: KeyedSubtree(key: _anchorKey, child: _buildDateExplorer(context, s, theme))),
        // ⑥ [판정286] 일자리 섹션 하나 — 날짜 영역 바로 아래. 미선택 「추천 일자리」 ↔ 선택 「M월 D일 일자리」 ·
        //   카드 최대 2 · 상태 안내와 맨 아래 탐색 행동 하나(일자리 관련 안내·버튼은 여기 한 곳뿐).
        _RhythmSlot(kind: _Rhythm.section, child: _buildRecommendSection(context, s, up)),
        // ⑦ 내 지원 현황 → 초대 → 이번 달 수입 → 내 근무 기록
        _RhythmSlot(kind: _Rhythm.section, child: _buildApplicationStatus(context, s)),
        _RhythmSlot(kind: _Rhythm.card, child: _buildInviteBanner(context, s, theme)),
        _RhythmSlot(kind: _Rhythm.section, child: _buildIncomeSection(context, s, theme)),
        _RhythmSlot(kind: _Rhythm.section, child: _buildCareerSection(context, s, up)),
      ]),
    );
  }

  /// [CP03] 화면 좌우 여백 — 폭 360 미만 16, 그 외 20(다시 s 를 곱하지 않는다).
  double _gutter(BuildContext context) => ConceptSpace.gutter(MediaQuery.sizeOf(context).width);

  /// [DU306 Standards §12.1] 머리 행동행 묶음 아래 → 계정 메타 위 = 합계 8(머리 아래 여백 0 + 이 값).
  ///   관리자 홈이 같이 쓰는 ConceptSpace.headerToHero(16)는 바꾸지 않는다(관리자 홈은 다음 묶음).
  static const double _kHeaderToMeta = 8;

  /// [CP03] 홈 섹션 머리 — 제목 20/700, 행동 14/700 brand + 꺾쇠 아이콘 1개(문자열에 `›` 없음), receiver ≥48.
  ///   실제 사용 폭에 제목(한 줄 필요 폭) + 행동이 들어가지 않으면 행동을 제목 아래 오른쪽 줄로 내린다(정밀 §8 B 규칙 2).
  ///   [actionText] 는 보이는 글자(줄바꿈 제어문자 포함 가능), [actionLabel] 은 의미 이름(없으면 actionText).
  Widget _sectionHeader(BuildContext context,
      {required String title, String? subtitle, String? actionText, String? actionLabel, VoidCallback? onAction}) {
    final titleText = Text(TextLayout.keepWords(title), style: ConceptText.section(), semanticsLabel: title);
    final head = subtitle == null
        ? titleText
        : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            titleText,
            const SizedBox(height: 4),
            Text(subtitle, style: ConceptText.meta()),
          ]);
    if (actionText == null || onAction == null) return head;
    // [wrap] 은 제목 아래 줄에 놓일 때만 — 그때는 폭이 정해져 있어 목적지 문구가 좁으면 줄을 바꾼다(말줄임·축소 없음).
    //   한 줄 배치(측정상 들어감)에서는 글자를 고정 폭으로 둔다(바깥 Row 의 비유연 자식).
    Widget action({required bool wrap}) {
      final label = Text(actionText, style: ConceptText.count().copyWith(height: 1.3));
      // [CP03 C1] excludeSemantics 가 아래 GestureDetector 의 tap 의미를 지운다 — 같은 콜백을 이 의미 노드에 둔다(독립 노드).
      return Semantics(
        container: true,
        button: true,
        label: actionLabel ?? actionText,
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
    return LayoutBuilder(builder: (context, c) {
      final need = _oneLineWidth(context, title, ConceptText.section()) + 8 + _actionWidth(context, actionText);
      if (need <= c.maxWidth) {
        return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: head),
          const SizedBox(width: 8),
          action(wrap: false),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        head,
        Align(alignment: Alignment.centerRight, child: action(wrap: true)),
      ]);
    });
  }

  /// [CP03] 한 줄 필요 폭 — 실제 글자 배율·DefaultTextStyle·locale 로 잰다(번들 글꼴).
  double _oneLineWidth(BuildContext context, String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  /// [CP03] 행동(글자 + 꺾쇠 18) 필요 폭 — 최소 receiver 48.
  double _actionWidth(BuildContext context, String text) {
    final w = _oneLineWidth(context, text, ConceptText.count().copyWith(height: 1.3)) + 18;
    return w < ConceptSpace.minTouch ? ConceptSpace.minTouch : w;
  }

  // ── 인사말 (시안 .greeting) ──────────────────────────────────
  Widget _buildGreeting(BuildContext context, double s, UserProvider up) {
    final user = up.currentUser;
    // [DU-VQ-01] 인사는 맥락일 뿐 다음 행동이 아니다 — 22sp 두 줄 + 구분선이 확정 카드보다 먼저 시선을 잡았다.
    //   한 줄(인사 보조색 + 이름 굵게)로 낮추고 구분선을 없앤다. 이름은 그대로 보인다(말줄임 없음, 길면 줄바꿈).
    // [DU1 구현69 VQ-01] 시안 '오늘도, 내 일정에 맞게 / 11월 5일 목요일' — 인사 아래 오늘 날짜(KST)로 화면 맥락을 준다.
    //   인사 크기는 후속14 결정대로 확정 카드보다 낮게 둔다(날짜는 보조색).
    final today = FormatHelper.toKstDate(_now());
    const wd = ['월', '화', '수', '목', '금', '토', '일'];
    // [CP03 Q1] 헤더 →16→ 계정 이름(14/400, 계정 메타) →4→ 큰 머리 `오늘도, 내 일정에 맞게`(24/700) →4→ KST 날짜(14/400).
    //   인사 조각은 큰 머리로 바꾸고 이름은 지우지 않고 메타로 옮긴다. 이름은 전문 그대로 자연 줄바꿈(말줄임 없음).
    //   큰 머리는 고정 문구라 낱말 사이에서만 줄을 바꾼다(의미 이름은 원문).
    final g = _gutter(context);
    return Padding(
      // [DU306 §12.1] 머리 →8→ 계정 메타(이전 머리 아래 10*s + 16 = W 25.2 / B 24.2).
      padding: EdgeInsets.fromLTRB(g, _kHeaderToMeta, g, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // [CP03 C1] 표시만 낱말 단위로 묶는다 — 긴 이름의 마지막 낱말과 `님`이 갈리지 않게(의미 이름·계정 원문 그대로).
        Text(TextLayout.keepWords('${user?.name ?? '사용자'}님'),
            style: ConceptText.meta(), semanticsLabel: '${user?.name ?? '사용자'}님'),
        const SizedBox(height: 4),
        Text(TextLayout.keepWords('오늘도, 내 일정에 맞게'),
            style: ConceptText.hero(), semanticsLabel: '오늘도, 내 일정에 맞게'),
        const SizedBox(height: ConceptSpace.heroToDate),
        Text('${today.month}월 ${today.day}일 ${wd[today.weekday - 1]}요일', style: ConceptText.meta()),
      ]),
    );
  }

  // ── 초대 배너 (INVITED 있을 때만 표시) ─────────────────────────
  Widget _buildInviteBanner(BuildContext context, double s, ThemeData theme) {
    final count = _invitedCount;
    if (count == 0) return const SizedBox.shrink();

    return Padding(
      // [CP03 Q9] 좌우 화면 여백만 — 위아래 간격은 본문 리듬(_RhythmColumn)이 맡는다.
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
      child: GestureDetector(
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            // 초대 탭(index 6) 바로 오픈
            builder: (_) => const MyApplicationsScreen(initialTabIndex: 6),
          ),
        ).then((_) { if (mounted) _loadHomeData(); }),
        // [DU306 Standards §12.2] 초대는 확정 상태가 아니다 — 넓은 녹색 gradient·녹색 그림자를 걷고,
        //   같은 홈의 '기다리는 요청' 카드(신분증 열람 요청)와 같은 brand 한 겹(바탕 .07·테두리 .32·채운 원 아이콘)으로 낮춘다.
        //   건수·문구·마감 안내·목적지(초대 탭 6)·복귀 갱신·0건 숨김은 그대로다.
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16 * s, vertical: 12 * s),
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.brand.withValues(alpha: 0.32)),
          ),
          child: Row(children: [
            Container(
              width: 38 * s,
              height: 38 * s,
              decoration: const BoxDecoration(
                color: AppColors.brand,
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
                    '업무 초대가 $count건 있어요',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 3 * s),
                  // [ISG2] 마감은 둘 중 **더 이른 쪽**이다 — 초대 후
                  //   24시간, 그리고 근무 시작. 어느 한쪽만 말하면 다른
                  //   쪽이 먼저 끝나는 경우를 숨긴다: 근무가 오늘 밤이면
                  //   24시간은 틀린 말이고, 다음 주 근무면 24시간이 먼저
                  //   끝난다. 건별 정확한 시각은 목록 카드가 말한다.
                  Text(
                    '초대 후 24시간과 근무 시작 중 빠른 때까지 수락할 수 있어요',
                    // 부제는 읽히는 보조색(textSecondary 5.92:1) — 흰 85% 글자를 녹색 위에 두던 것을 대신한다.
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8 * s),
            Icon(Icons.chevron_right, color: AppColors.brand, size: 20 * s),
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
  // ── 자정을 넘겨 아직 퇴근하지 않은 근무 ────────────────────────
  //
  // [R7-P2-1 잔여 · UHR-18] 출퇴근 화면은 **어제 날짜의 진행 중 기록**을
  //   목록에 남긴다(자정 넘겨 퇴근하는 근무). 홈 Hero 는 오늘만 보므로,
  //   퇴근만 남은 사람에게 홈에서 갈 길이 없었다.
  //
  //   자격은 "어제 날짜 확정 근무"가 아니라 **실제로 출근했고 퇴근이 남은
  //   진행 중인 기록**이다. 목적지(`attendance_check_screen`)가 어제 기록을
  //   숨기는 조건과 같은 술어를 쓴다 — 두 화면이 다른 대상을 말하지 않는다:
  //     · `checkOut != null`            → 이미 퇴근
  //     · `missed_checkout`             → 자동 처리됨
  //     · `NO_SHOW` / `absent`          → 출근 자체가 없다
  //   여기에 홈 쪽 조건을 더한다:
  //     · `checkIn == null`             → 미출근이면 퇴근 CTA 를 만들지 않는다
  //     · 지원서가 `confirmedStatuses` 가 아니면 제외(취소·해지)
  //     · `userId` 재확인 — self-uid 계약을 화면에서도 깨지 않는다
  // ── 오늘 근무의 실제 근태 기록 ────────────────────────────────
  //
  // [E1-HACI] Hero(STATE B)는 진행 라벨·진행 바·CTA 를 **시계만 보고** 정했다.
  //   그래서 출근 기록이 없는 근무도 종료 시각이 지나면 `근무 완료` + 100% 로
  //   그려지고, 그 아래에 `출근하기` 버튼이 함께 떴다 — 한 카드가 서로
  //   모순되는 두 사실을 말했다(DEV 실측: 2026-10-13 10:00~11:00 확정 근무,
  //   근태 문서 0건).
  //
  //   매칭 술어는 새로 만들지 않는다 — `_openOvernightAttendance` 와
  //   `_rebuildCaches` 가 이미 쓰는 `userId` + `applicationId` 한 벌이고,
  //   목적지(`attendance_check_screen`)도 같은 `applicationId` 로 조회한다.
  //   읽기도 추가하지 않는다: `_attendances` 가 이번 달(KST) 전체 근태이므로
  //   오늘 건은 이미 메모리에 있다.
  //
  //   날짜는 `att.workDate` 로 본다(`app.workDate` 아님) — 장기 근무의
  //   `app.workDate` 는 계약 시작일 고정값이다.
  AttendanceModel? _todayAttendanceFor(ApplicationModel app) {
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) return null;
    final today = FormatHelper.toKstDate(_now());
    for (final att in _attendances) {
      if (att.userId != uid) continue;
      if (att.applicationId != app.id) continue;
      if (FormatHelper.toKstDate(att.workDate) != today) continue;
      return att;
    }
    return null;
  }

  AttendanceModel? _openOvernightAttendance() {
    final uid = context.read<UserProvider>().currentUser?.uid;
    if (uid == null) return null;
    // 지원 내역을 못 읽었으면 확정 여부를 확인할 수 없다 — 거짓 CTA 금지.
    if (_homeLoadFailed) return null;
    final yesterday =
        FormatHelper.toKstDate(_now()).subtract(const Duration(days: 1));

    for (final att in [..._attendances, ..._prevMonthTail]) {
      if (att.userId != uid) continue;
      if (FormatHelper.toKstDate(att.workDate) != yesterday) continue;
      if (att.checkInAt == null) continue;   // 출근하지 않았다
      if (att.checkOutAt != null) continue;  // 이미 퇴근했다
      if (att.status == 'missed_checkout' ||
          att.status == AttendanceModel.statusNoShow ||
          att.status == AttendanceModel.statusAbsent) {
        continue;
      }
      final app = _applications
          .where((a) => a.id == att.applicationId)
          .firstOrNull;
      if (app == null) continue;
      if (!AppStatus.confirmedStatuses.contains(app.status)) continue;
      return att;
    }
    return null;
  }

  Widget _buildOvernightCheckoutCard(BuildContext context, double s) {
    // [PERF-P1] 첫 1라운드 전·구역 첫 표시 전에는 그리지 않는다. 재조회 중에는 마지막 값을 그대로 둔다.
    if (!_zoneRevealed || !_mainRoundDone) return const SizedBox.shrink();

    // [ERROR ≠ EMPTY] 못 읽었으면 "퇴근이 남지 않았다"고 말하지 않는다.
    if (_overnightUnknown) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: _gutter(context)), // [CP03 Q9]
        child: GestureDetector(
          onTap: _isLoadingData ? null : () => _loadHomeData(),
          child: Container(
            padding:
                EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(children: [
              Icon(Icons.cloud_off_outlined,
                  size: 20 * s, color: AppColors.textSecondary),
              SizedBox(width: 10 * s),
              Expanded(
                child: Text(
                  '어제 근무의 퇴근 여부를 확인하지 못했어요',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              SizedBox(width: 8 * s),
              // [DU306 §12.2] 재시도 = 일반 진행 행동 → brand(예전 파랑 infoDark #1976D2 대신). 카드 전체 탭·목적지 그대로.
              Text('다시 시도',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                  )),
            ]),
          ),
        ),
      );
    }

    final att = _openOvernightAttendance();
    if (att == null) return const SizedBox.shrink();

    final wd = FormatHelper.toKstDate(att.workDate);
    final started = att.checkIn; // HH:mm — 반올림 적용 후 최종 출근 시각
    const accent = AppColors.warning;
    final subtitle = [
      '${wd.month}/${wd.day} 근무',
      if (att.businessName.isNotEmpty) att.businessName,
      if (started != null) '$started 출근',
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)), // [CP03 Q9]
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
                builder: (_) => const AttendanceCheckScreen()),
          );
          if (mounted) _loadHomeData();
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.32)),
          ),
          // [CP03] 정밀 §8 B 규칙 1 — 필수 행동 문구는 말줄임 없이 전문(자연 줄바꿈).
          // [CP03 C1] 제목·부제는 낱말(부제는 구분점 조각) 사이에서만 줄을 바꾸고, 본문 폭이 모자라면 `퇴근하기`를 아래 오른쪽 줄로.
          child: _taskCardRow(
            context,
            s,
            icon: Container(
              width: 38 * s,
              height: 38 * s,
              decoration:
                  const BoxDecoration(color: accent, shape: BoxShape.circle),
              child: Icon(Icons.logout_rounded,
                  size: 20 * s, color: Colors.white),
            ),
            iconWidth: 38 * s,
            title: '퇴근 기록이 필요해요',
            titleDisplay: TextLayout.keepWords('퇴근 기록이 필요해요'),
            titleStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            subtitle: subtitle,
            subtitleDisplay: TextLayout.phrases(subtitle),
            subtitleStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            actionText: '퇴근하기',
            actionStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accent),
          ),
        ),
      ),
    );
  }

  /// [CP03 C1] 필수응답 카드(미퇴근·신분증 열람 요청) 안쪽 — 아이콘 · 본문(제목·부제 전문, 자연 높이) · 행동 글자.
  ///   필요 폭 = 제목·부제 표시 문자열의 가장 긴 낱말 단위(공백으로 나눈 조각) 한 줄 폭(실제 배율·DefaultTextStyle·locale).
  ///   행동을 같은 줄에 둘 때 본문에 남는 폭이 그보다 좁으면 행동을 본문 아래 오른쪽 줄로 내린다(말줄임·축소 없음).
  ///   [CP03 C1 r3] 같은 줄은 본문에 남는 폭이 **아이콘을 포함한 안쪽 전체 가용 폭(c.maxWidth)의 절반 이상**일 때만이다.
  ///   낱말 하나만 겨우 들어가는 좁은 기둥(B 미퇴근 115.5px, 제목 3줄·부제 6줄)을 막는다
  ///   (records/requests/DU_concept_CP03_c1_r3_resume_2026-11-12.md §2).
  ///   행동 글자는 따로 누르는 곳이 아니다 — 카드 전체 탭·목적지·표시 조건은 호출부 그대로다.
  Widget _taskCardRow(
    BuildContext context,
    double s, {
    required Widget icon,
    required double iconWidth,
    required String title,
    required String titleDisplay,
    required TextStyle titleStyle,
    required String subtitle,
    required String subtitleDisplay,
    required TextStyle subtitleStyle,
    required String actionText,
    required TextStyle actionStyle,
    Widget? actionTrailing,
    double actionTrailingWidth = 0,
    String? note,
    TextStyle noteStyle = const TextStyle(),
  }) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(titleDisplay, style: titleStyle, semanticsLabel: title),
        SizedBox(height: 3 * s),
        Text(subtitleDisplay, style: subtitleStyle, semanticsLabel: subtitle),
        // [DU595c · 판정177 §6] 셋째 줄(서류 보완 카드의 급여 안내) — 있을 때만 · 같은 낱말 조판 · 원문 이름. 다른 호출부는 넘기지 않는다(그대로).
        if (note != null) ...[
          SizedBox(height: 3 * s),
          Text(TextLayout.keepWords(note), style: noteStyle, semanticsLabel: note),
        ],
      ],
    );
    // [wrap] 은 아래 줄에 놓일 때만 — 그때는 폭이 정해져 있다(바깥 Row 의 비유연 자식일 때는 고정 폭 글자).
    Widget action({required bool wrap}) {
      final label = Text(actionText, style: actionStyle);
      return Row(mainAxisSize: MainAxisSize.min, children: [
        if (wrap) Flexible(child: label) else label,
        if (actionTrailing != null) actionTrailing,
      ]);
    }

    return LayoutBuilder(builder: (context, c) {
      double widest(String display, TextStyle style) {
        var w = 0.0;
        for (final unit in display.split(' ')) {
          if (unit.isEmpty) continue;
          final uw = _oneLineWidth(context, unit, style);
          if (uw > w) w = uw;
        }
        return w;
      }

      final tw = widest(titleDisplay, titleStyle);
      final sw = widest(subtitleDisplay, subtitleStyle);
      // [DU595c] 셋째 줄이 있으면 그 낱말 폭도 본다(없으면 0 — 다른 카드의 판정 그대로).
      final nw = note == null ? 0.0 : widest(TextLayout.keepWords(note), noteStyle);
      final need = [tw, sw, nw].reduce((a, b) => a > b ? a : b);
      final actionW = _oneLineWidth(context, actionText, actionStyle) + actionTrailingWidth;
      final inlineBody = c.maxWidth - iconWidth - 12 * s - 8 * s - actionW;
      if (inlineBody >= need && inlineBody >= c.maxWidth * 0.5) {
        return Row(children: [
          icon,
          SizedBox(width: 12 * s),
          Expanded(child: body),
          SizedBox(width: 8 * s),
          action(wrap: false),
        ]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            icon,
            SizedBox(width: 12 * s),
            Expanded(child: body),
          ]),
          SizedBox(height: 8 * s),
          Align(alignment: Alignment.centerRight, child: action(wrap: true)),
        ],
      );
    });
  }

  Widget _buildPriorityCard(BuildContext context, double s, ThemeData theme) {
    final g = _gutter(context);
    // 로딩 중: skeleton (State B/A 여부 미확정이므로 자리 유지)
    // [PERF-P1] 구역 첫 표시 전 · 첫 1라운드 전 · (오늘 약속이 없는데) 확인한 새 확정 목록 복원 전 = 구역 전체의 '확인 중' 자리.
    //   재조회 중(_mainRoundDone)에는 뼈대로 돌아가지 않고 마지막 약속을 그대로 둔다.
    if (_promisePlaceholder) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: g),
        child: Semantics(
          key: const ValueKey('worker-home-required-pending'),
          container: true,
          label: '오늘 할 일을 확인하고 있어요',
          child: Container(
            height: 90 * s,
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }
    // [CP03 Q3·Q4·Q7] 섹션 제목은 카드 밖(20/700, 장식 점 없음) →12→ 카드.
    Widget section(String title, Widget card) => Padding(
          padding: EdgeInsets.symmetric(horizontal: g),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _sectionHeader(context, title: title),
            const SizedBox(height: ConceptSpace.sectionTitleToCard),
            card,
          ]),
        );
    // State B: 오늘 출근 (최우선)
    if (_heroTodayApp != null) {
      return section('오늘의 약속', _buildHeroStateB(context, s, _heroTodayApp!));
    }
    // State A: 새 확정 미확인
    if (_heroNewConfirmApp != null) {
      return section('새로 확정된 근무', _buildHeroStateA(context, s, _heroNewConfirmApp!));
    }
    // [판정285 §2 — CP03 Q7 대체] 정상 약속 0 의 큰 「오늘의 약속」 카드와 그 안의 `일자리 찾기` 는 없앴다.
    //   "오늘 확정된 근무가 없어요" 는 통합 날짜 영역이 한 번 말한다([_todayZeroNotice] — 같은 조건:
    //   로딩 끝·지원 조회 성공·B/A 없음). 지원 조회 실패·이전 값 유지(stale)는 여전히 0 으로 말하지 않는다.
    return const SizedBox.shrink();
  }

  /// [판정285 §2] 오늘 정상 0 — 미선택·로딩 끝·지원 조회 성공·실제 약속(B/A) 없음일 때만.
  ///   옛 큰 카드의 조건(`!_homeLoadFailed`)과 같다. 날짜를 고르면 선택일 상태로 바뀐다.
  bool get _todayZeroNotice =>
      _selectedDateChip == null && _mainRoundDone && !_homeLoadFailed && !_hasPromiseHero &&
      !_applicationsMaybePartial; // [판정287 C287-01] 200 건 상한으로 일부만 읽었으면 오늘 0 을 단정하지 않는다

  /// [판정287 C287-01] 오늘 0 을 단정할 수 없는 경우 — 일부만 읽음(200 건 상한)인데 읽은 목록에 오늘 약속이 없다.
  ///   정상 0 대신 미확인 안내를 한 번 말한다(새 전량 조회 0).
  bool get _todayPartialNotice =>
      _selectedDateChip == null && _mainRoundDone && !_homeLoadFailed && !_hasPromiseHero &&
      _applicationsMaybePartial;

  /// [CP03 Q4] 큰 시간 — `HH:mm` 과 `–HH:mm` 두 토큰 사이에서만 줄을 바꾼다(시각 안 숫자는 나누지 않는다). 의미는 원문 한 줄.
  Widget _promiseTime(String start, String end) {
    return Semantics(
      label: '$start–$end',
      excludeSemantics: true,
      child: Wrap(children: [
        Text(start, style: ConceptText.promiseTime()),
        Text('–$end', style: ConceptText.promiseTime()),
      ]),
    );
  }

  // ── 날짜 기반 일자리 탐색 — 상시 노출 (Priority Card와 독립) ──
  // 확정/출근 유무와 무관하게 항상 표시. ALfit의 핵심 탐색 기능.
  Widget _buildDateExplorer(BuildContext context, double s, ThemeData theme) {
    // [판정285 §2] 시작 준비 아래 한 섹션(섹션 사이는 본문 리듬) — 좌우 화면 여백만. 안쪽 카드·테두리 없음.
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
      child: _buildHeroStateC(context, s, theme),
    );
  }

  /// [DEVICE-MISMATCH-FIX] Hero 제목 — 진행 라벨·CTA 와 **같은 판정 순서**
  ///   (조회 실패 → 노쇼·결근 → 퇴근 → 출근 → 종료 → 출근 전).
  ///   근태를 못 읽었으면 출근 전이라고도, 끝났다고도 단정하지 않는다.
  String _heroTitle(
    ApplicationModel app, {
    required bool hasTime,
    required bool attUnknown,
    required bool isNoShow,
    required bool isAbsent,
    required bool hasCheckedIn,
    required bool hasCheckedOut,
  }) {
    final at = hasTime ? '${app.startTime} ' : '';
    if (attUnknown) return hasTime ? '오늘 ${app.startTime} 근무가 있어요' : '오늘 근무가 있어요';
    if (isNoShow) return '오늘 근무가 노쇼 처리됐어요';
    if (isAbsent) return '오늘 근무가 결근 처리됐어요';
    if (hasCheckedOut) return '오늘 근무를 마쳤어요';
    if (hasCheckedIn) return '오늘 근무 중이에요';
    if (app.hasShiftEndedAt(_now())) return '오늘 $at근무 시간이 지났어요';
    return hasTime ? '오늘 ${app.startTime} 출근이에요' : '오늘 근무가 있어요';
  }

  // ── STATE B: 오늘 출퇴근 (시안 .hB) ──────────────────────────
  Widget _buildHeroStateB(BuildContext context, double s, ApplicationModel app) {
    final hasTime = app.startTime.isNotEmpty && app.endTime.isNotEmpty;

    // [E1-HACI] 상태의 주인은 근태 기록이다. 시계는 **아직 하지 않은 일**의
    //   남은 시간만 말한다 — 시간이 지났다는 이유로 출근·퇴근·완료를
    //   확정하지 않는다. 근태를 못 읽었으면(UNKNOWN) 완료도 미출근도
    //   단정하지 않는다(ERROR ≠ ZERO).
    final attUnknown = _attendancesFailed;
    final att = attUnknown ? null : _todayAttendanceFor(app);
    final isNoShow = att?.status == AttendanceModel.statusNoShow;
    final isAbsent = att?.status == AttendanceModel.statusAbsent;
    final hasCheckedIn = att?.hasCheckedIn ?? false;
    final hasCheckedOut = att?.hasCheckedOut ?? false;

    // 카운트다운 진행 상태 계산
    String progressLabel = '출근 준비 중';
    double progressValue = 0.0;
    // 사실을 말하는 라벨(완료·노쇼·결근·조회 실패)은 진행 안내와 색을 달리한다.
    // [DU306 §12.2] 일반 진행(출근 준비·출근까지·퇴근까지)은 brand — 같은 카드의 출근/퇴근 CTA 와 한 색.
    //   아래 사실 분기(조회 실패 grey600·노쇼/결근 errorDark·기록 없음 warningDark·완료 successDark)는 그대로다.
    Color progressColor = AppColors.brand;
    if (attUnknown) {
      // 근태를 못 읽었다 — `근무 완료`도 `출근 기록 없음`도 말할 수 없다.
      progressLabel = '근태 기록을 불러오지 못했어요';
      progressColor = AppColors.grey600;
    } else if (isNoShow || isAbsent) {
      // 목적지 화면과 같은 문구 — 노쇼·결근을 근무 완료로 바꿔 말하지 않는다.
      progressLabel = isNoShow ? '노쇼 처리됨' : '결근 처리됨';
      // [DU595b · 판정139 §3 :44 PP-STATUS-PAIR] 명시 결근 결과 = 노쇼와 같은 error 짝(진한 글 errorDark) — 출근 기록 없음 · 퇴근 필요는 warning 그대로.
      progressColor = AppColors.errorDark;
    } else if (hasCheckedOut) {
      // 퇴근 기록이 있을 때만 완료다. 근태 확정(급여) 여부는 별개이므로
      // 여기서 `근태 확정`이라고 말하지 않는다.
      progressLabel = '출퇴근 완료';
      progressValue = 1.0;
      progressColor = AppColors.successDark;
    } else if (hasTime) {
      // [E1-TZ] 근무 시각의 기준은 기기 시간대가 아니라 canonical KST 다.
      //   예전에는 KST 벽시계 문자열(`startTime`)을 **기기 local 자정**에
      //   더했다. 그래서 GMT 기기에서 10:00 근무가 19:00 로 해석돼
      //   "출근까지 9시간" 같은 잘못된 안내가 나왔다(DEV 에뮬레이터 실측).
      //   날짜도 '오늘'이 아니라 **그 근무의 KST 날짜**에서 출발한다.
      final now = _now();
      final kstDay = FormatHelper.toKstDate(app.workDate);
      final startDt = FormatHelper.kstWallClockInstant(kstDay, app.startTime);
      var endDt = FormatHelper.kstWallClockInstant(kstDay, app.endTime);
      if (startDt == null || endDt == null) {
        // 시각을 못 읽었다 — 남은 시간을 지어내지 않는다.
        progressLabel = '출근 준비 중';
      } else {
        // 자정을 넘기는 근무(23:00~01:00)는 종료가 다음 날이다.
        if (!endDt.isAfter(startDt)) {
          endDt = endDt.add(const Duration(days: 1));
        }
        if (now.isBefore(startDt) && hasCheckedIn) {
          // [UI-4] 일찍 출근한 경우 — 제목은 `근무 중`인데 `출근까지 N분`(0%)이
          //   함께 나와 서로 다른 말을 했다(LOCAL 실측). 출근 사실을 말한다.
          progressLabel = '출근했어요 · ${app.startTime} 시작';
          progressColor = AppColors.successDark;
        } else if (now.isBefore(startDt)) {
          final rem = startDt.difference(now);
          final h = rem.inHours;
          final m = rem.inMinutes % 60;
          progressLabel = h > 0 ? '출근까지 $h시간 $m분' : '출근까지 $m분';
        } else if (!hasCheckedIn) {
          // 시작 시각이 지났는데 출근 기록이 없다 — 완료가 아니다.
          // [DEVICE-MISMATCH-FIX] 종료까지 지났으면 그 사실을 말한다.
          progressLabel = now.isBefore(endDt)
              ? '출근 기록이 없어요'
              : '근무 시간이 지났어요 · 출근 기록이 없어요';
          progressColor = AppColors.warningDark;
        } else if (now.isAfter(endDt)) {
          // 출근은 했고 퇴근만 남았다. 시간 경과로 퇴근을 기록하지 않는다.
          progressValue = 1.0;
          progressLabel = '퇴근 기록이 필요해요';
          progressColor = AppColors.warningDark;
        } else {
          final total = endDt.difference(startDt).inMinutes;
          final elapsed = now.difference(startDt).inMinutes;
          progressValue = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 0;
          final rem = endDt.difference(now);
          final h = rem.inHours;
          final m = rem.inMinutes % 60;
          progressLabel = h > 0 ? '퇴근까지 $h시간 $m분' : '퇴근까지 $m분';
        }
      }
    }

    // CTA — 목적지(`attendance_check_screen`)의 4분기와 같은 순서·같은 술어.
    //   목적지는 바꾸지 않는다(그 화면이 출퇴근 canonical writer). 여기서는
    //   **무엇을 할 차례인지**만 같은 사실로 말한다.
    final String ctaLabel;
    final IconData ctaIcon;
    final Color ctaColor;
    // [CONTRACT-DISPATCH-B4] 출근 전에는 출퇴근 화면과 **같은 계약 판정**을 쓴다(그 화면이 버튼을 닫는 조건).
    //   이미 출근했으면 보지 않는다 — 퇴근 입구를 계약으로 막지 않는다.
    final contractGate = CheckInContractGate.evaluate(
        work: app,
        uid: context.read<UserProvider>().currentUser?.uid ?? '',
        contracts: _contracts);
    final EmploymentContractModel? signContract = contractGate.signable;
    if (attUnknown) {
      ctaLabel = '출퇴근 화면에서 확인';
      ctaIcon = Icons.help_outline_rounded;
      ctaColor = AppColors.grey600;
    } else if (isNoShow || isAbsent) {
      // 출근을 요구하지 않는다 — 이미 처리된 상태다.
      ctaLabel = '근태 기록 확인';
      ctaIcon = Icons.info_outline_rounded;
      ctaColor = AppColors.grey600;
    } else if (!hasCheckedIn && app.hasShiftEndedAt(_now())) {
      // [DEVICE-MISMATCH-FIX] 예정 시간이 끝난 근무에 `출근하기`를 권하지
      //   않는다. 목적지 화면도 이 경우 버튼을 닫는다.
      ctaLabel = '근태 기록 확인';
      ctaIcon = Icons.info_outline_rounded;
      ctaColor = AppColors.grey600;
    } else if (!hasCheckedIn &&
        contractGate.state == CheckInContractState.workerPending) {
      // 근로자가 지금 할 수 있는 일 — 그 계약으로 바로 간다.
      ctaLabel = '계약서 확인하고 동의하기';
      ctaIcon = Icons.draw_outlined;
      ctaColor = AppColors.brand;
    } else if (!hasCheckedIn &&
        (contractGate.state == CheckInContractState.missing ||
            contractGate.state == CheckInContractState.employerPending)) {
      // 근로자가 할 수 없는 일(사업장 발송·서명)을 요구하지 않는다 — 기다림을 말한다.
      ctaLabel = '계약서를 기다리고 있어요';
      ctaIcon = Icons.hourglass_top_rounded;
      ctaColor = AppColors.grey600;
    } else if (!hasCheckedIn &&
        contractGate.state == CheckInContractState.unknown) {
      ctaLabel = '출퇴근 화면에서 확인';
      ctaIcon = Icons.help_outline_rounded;
      ctaColor = AppColors.grey600;
    } else if (!hasCheckedIn) {
      ctaLabel = '출근하기';
      ctaIcon = Icons.login_rounded;
      ctaColor = AppColors.brand;
    } else if (!hasCheckedOut) {
      ctaLabel = '퇴근하기';
      ctaIcon = Icons.logout_rounded;
      ctaColor = AppColors.brand;
    } else {
      ctaLabel = '출퇴근 기록 보기';
      ctaIcon = Icons.check_circle_outline_rounded;
      // [DU306 §12.2·§9.1] 상태색이 버튼색을 정하지 않는다 — 완료 사실은 위 진행 라벨 `출퇴근 완료`(successDark)가 말한다.
      //   기록 보기는 같은 자리의 다른 확인 입구(`근태 기록 확인`)와 같은 중립 테두리·grey600 글자.
      ctaColor = AppColors.grey600;
    }

    // [CP03 Q3] 오늘 약속 카드 — conceptPromise 한 겹. 섹션 제목 `오늘의 약속` 은 카드 밖(_buildPriorityCard).
    //   기존 7종 상태 제목 16/700 →12→ 사업장 20/700 →4→ 업무 16/400(있을 때) →8→ 시간 28/700(hasTime) →4→
    //   요율 14/400(app.wage > 0 일 때만, A 와 같은 formatter) → [12 → 약한 구분선 → 12 → 진행 라벨 13/700 →8→ 막대 6](hasTime)
    //   →16→ 기존 CTA(전폭·최소 52·반경 12). 별도 `근무 확정` 필은 두지 않는다(노쇼·결근 포함 B 전체).
    //   글자는 전부 실제 배율·자연 줄바꿈(말줄임·축소·고정 높이 없음). 진행 표시 조건·라벨·값·색은 그대로다.
    final heroTitle = _heroTitle(app,
        hasTime: hasTime,
        attUnknown: attUnknown,
        isNoShow: isNoShow,
        isAbsent: isAbsent,
        hasCheckedIn: hasCheckedIn,
        hasCheckedOut: hasCheckedOut);
    final wageType = app.wageType; // 없으면 라벨을 지어내지 않는다
    final showWage = app.wage > 0; // 모델이 누락 wage 를 0 으로 읽는다 — 0 이하이면 줄과 간격을 두지 않는다
    // [F293-WAGE-01] 예상 단계(퇴근 전)의 시급 약속은 하루 예상 + 시급 — 이 카드가 보여 주는 app 시각으로 계산.
    //   퇴근 뒤는 예전 표시(산정 금액 미공개 HB3 를 예상액으로 대신하지 않는다).
    final expectedLine = hasCheckedOut
        ? null
        : ExpectedWageText.combined(ExpectedDailyWage.forPromise(
            wageType: wageType, rate: app.wage, startTime: app.startTime,
            endTime: app.endTime, breakMinutes: app.breakMinutes));
    final wageStr = expectedLine ??
        (wageType != null
            ? FormatHelper.formatWageWithType(app.wage, wageType)
            : FormatHelper.formatWage(app.wage));
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(ConceptSpace.cardPadding),
        decoration: ConceptSurface.promise(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상태 제목 — 진행 라벨·CTA 와 같은 근태 사실(7종 그대로).
            // [DEVICE-MISMATCH-FIX] DEVICE(10-20): 출퇴근을 마친 RUBE 에 `출퇴근 완료` 바로 위 제목이
            //   여전히 `오늘 13:00 출근이에요`(앞으로 출근할 것처럼)였다.
            // [CP03 C1] 표시만 낱말 사이에서 줄바꿈(7종 문구·분기·색 그대로), 의미 이름은 원문.
            Text(
              TextLayout.keepWords(heroTitle),
              semanticsLabel: heroTitle,
              style: ConceptText.taskTitle().copyWith(fontSize: 16, height: 1.3),
            ),
            const SizedBox(height: ConceptSpace.promiseChipToBusiness),
            Text(TextLayout.keepWords(app.businessName),
                style: ConceptText.promiseBusiness(), semanticsLabel: app.businessName),
            if (app.selectedWorkType.isNotEmpty) ...[
              const SizedBox(height: ConceptSpace.promiseBusinessToWork),
              Text(TextLayout.keepWords(app.selectedWorkType),
                  style: ConceptText.body(color: AppColors.textSecondary), semanticsLabel: app.selectedWorkType),
            ],
            if (hasTime) ...[
              const SizedBox(height: ConceptSpace.promiseWorkToTime),
              _promiseTime(app.startTime, app.endTime),
            ],
            if (showWage) ...[
              const SizedBox(height: ConceptSpace.promiseTimeToRate),
              Text(wageStr, style: ConceptText.meta()),
            ],
            // 진행 — 중첩 흰 상자 없이 약한 구분선 아래 행으로(정밀 §6 conceptPromise).
            if (hasTime) ...[
              const SizedBox(height: ConceptSpace.infoGroupGap),
              Container(height: 1, color: AppColors.conceptCardBorder),
              const SizedBox(height: ConceptSpace.infoGroupGap),
              Text(progressLabel,
                  style: ConceptText.pill(progressColor)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressValue,
                  minHeight: 6,
                  // [DU306 §12.2] 막대 바탕 = brand 계열 옅은 면(brandSurface) — 예전 파랑 바탕(infoBg) 대신.
                  backgroundColor: AppColors.brandSurface,
                  color: progressColor,
                ),
              ),
            ],
            const SizedBox(height: ConceptSpace.infoToCta),
            // 출퇴근 CTA — 문구·색·분기·목적지·복귀 갱신은 그대로. 최소 52·반경 12·내용만큼 자연 높이.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                // [ATTENDANCE-SCREEN-REFRESH] 출퇴근은 목적지 화면에서 일어난다 — 돌아오면
                //   다시 읽는다. 예전에는 복귀 뒤에도 출근 전 Hero('출근까지 N분·출근하기')가
                //   앱 복귀·새로고침 전까지 남았다(DEVICE 10/20 12:37). 같은 파일의 다른
                //   push 복귀와 같은 패턴이고, 근태 캐시는 출퇴근 성공 시 서비스가 이미 비운다.
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => (!hasCheckedIn && signContract != null)
                            ? ContractSignScreen(
                                contract: signContract, role: 'worker')
                            : const AttendanceCheckScreen()))
                    .then((_) { if (mounted) _loadHomeData(); }),
                icon: Icon(ctaIcon, size: 18),
                // [CP03 C1] 표시만 낱말 사이에서 줄바꿈(문구·분기 그대로), 의미 이름은 원문.
                label: Text(TextLayout.keepWords(ctaLabel),
                    semanticsLabel: ctaLabel,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, height: 1.3)),
                // [UI-4] 지금 근로자가 할 행동(계약 동의·출근·퇴근)만 브랜드 채움.
                //   기다림·확인 입구(계약 대기·근태 확인·기록 보기)는 진한 회색
                //   채움이 비활성 버튼처럼 보였다 — 중립 테두리로 낮춘다(눌리는 건 같다).
                // [CP03 Q3] 최소 52·반경 12·글자 16/700(정밀 §8 상태필/버튼), 높이는 내용만큼 자연 확장.
                style: ctaColor == AppColors.brand
                    ? ElevatedButton.styleFrom(
                        backgroundColor: ctaColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(ConceptSpace.primaryCtaMinHeight),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      )
                    : ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: ctaColor,
                        minimumSize: const Size.fromHeight(ConceptSpace.primaryCtaMinHeight),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: AppColors.border)),
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
    // [R1.2] workDate는 KST calendar date — 기기 timezone으로 읽으면 하루 밀린다.
    final kstDate = FormatHelper.toKstDate(app.workDate);
    final dateStr = '${kstDate.month}월 ${kstDate.day}일';
    final hasTime = app.startTime.isNotEmpty && app.endTime.isNotEmpty;
    // [DU1-F2] 금액 단위 — 저장 wageType 의 기존 라벨(시급/일급). 실수령 새 계산은 하지 않는다.
    // [F293-WAGE-01] 시급 약속은 하루 예상(세전 · 무급 휴게 차감) + 시급 — 이 카드가 보여 주는 app 시각으로 계산.
    final wageType = app.wageType; // 없으면 라벨을 지어내지 않는다
    final wageStr = ExpectedWageText.combined(ExpectedDailyWage.forPromise(
            wageType: wageType, rate: app.wage, startTime: app.startTime,
            endTime: app.endTime, breakMinutes: app.breakMinutes)) ??
        (wageType != null
            ? FormatHelper.formatWageWithType(app.wage, wageType)
            : FormatHelper.formatWage(app.wage));

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
        width: double.infinity,
        padding: const EdgeInsets.all(ConceptSpace.cardPadding),
        // [CP03 Q4] 새 확정 약속 — conceptPromise 한 겹. 섹션 제목 `새로 확정된 근무` 는 카드 밖(_buildPriorityCard).
        decoration: ConceptSurface.promise(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상태 묶음 — `근무 확정` 필(conceptConfirmed, 13/700 #166534) + `근무가 확정됐어요`(13/400). 넘치면 다음 줄·자연 높이.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: ConceptSurface.confirmed(),
                  child: Text('근무 확정', style: ConceptText.pill(AppColors.successDark)), // #166534
                ),
                Text('근무가 확정됐어요',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400, height: 1.3, color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: ConceptSpace.promiseChipToBusiness),
            // [CP03 Q5] A 는 모든 폭에서 기존 날짜·시간 선행을 유지한다(DU1 구현69: 320·2.0 에서 긴 사업장명이 시간을 밀었다).
            //   상태 →12→ KST 날짜 14/400 →4→ 시간 28/700 →12→ 사업장 20/700 →4→ 업무 16/400 →4→ 요율 →16→ CTA. 없는 필드는 간격도 없다.
            Text(
                '$dateStr(${const ['월', '화', '수', '목', '금', '토', '일'][kstDate.weekday - 1]})',
                style: ConceptText.meta()),
            if (hasTime) ...[
              const SizedBox(height: 4),
              _promiseTime(app.startTime, app.endTime),
            ],
            const SizedBox(height: ConceptSpace.infoGroupGap),
            // 낱말 단위 줄바꿈(음절 끊김 금지) — '2|공장'·'검|수'(H35-B after r1). 의미 이름은 원문.
            Text(TextLayout.keepWords(app.businessName),
                style: ConceptText.promiseBusiness(), semanticsLabel: app.businessName),
            if (app.selectedWorkType.isNotEmpty) ...[
              const SizedBox(height: ConceptSpace.promiseBusinessToWork),
              Text(TextLayout.keepWords(app.selectedWorkType),
                  style: ConceptText.body(color: AppColors.textSecondary), semanticsLabel: app.selectedWorkType),
            ],
            const SizedBox(height: 4),
            _heroInfoRow(s, Icons.payments_outlined, wageStr),
            const SizedBox(height: ConceptSpace.infoToCta),
            // 주 행동 — 카드 전체가 같은 탭 대상이라 별도 버튼 위젯이 아니라 모양만 준다. 최소 52·반경 12.
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: ConceptSpace.primaryCtaMinHeight),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.brand,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('근무 확인하기', style: ConceptText.button()),
            ),
          ],
        ),
      ),
    );
  }

  /// [DU-VQ-01] 확정 카드 정보 행 — 아이콘 + 글자(넘치면 줄바꿈, 말줄임 없음).
  Widget _heroInfoRow(double s, IconData icon, String text, {bool strong = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 2 * s),
          child: Icon(icon, size: 15 * s, color: AppColors.textSecondary),
        ),
        SizedBox(width: 6 * s),
        Expanded(
          child: Text(text,
              style: TextStyle(
                fontSize: strong ? 14 : 13,
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                color: strong ? AppColors.textPrimary : AppColors.textSecondary,
                height: 1.35,
              )),
        ),
      ],
    );
  }

  // ── 날짜 더보기 — 월간 캘린더 BottomSheet ─────────────────────────
  // 현재 7일 범위 밖의 날짜를 선택할 수 있게 한다.
  // 선택 시: _stripStart = 선택일, _selectedDateChip = 선택일, 캐시 재계산
  Future<void> _showDatePickerSheet(BuildContext context, double s) async {
    final now = _now();
    final today = FormatHelper.toKstDate(now);
    DateTime focusedDay = _selectedDateChip ?? _stripStart;

    await DialogHelper.showSheet<void>(
      context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheet) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16 * s, 8 * s, 16 * s, 16 * s),
            // [DU191] 큰 글자·좁은 화면에서 시트 내용이 높이를 넘으면 시트 안에서만 세로 스크롤한다(내용·순서·여백·SafeArea 그대로).
            child: SingleChildScrollView(
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
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
                SizedBox(height: 8 * s),
                AppCalendar(
                  focusedDay: focusedDay,
                  selectedDay: _selectedDateChip,
                  // [DU193] 시트 세로 스크롤과 겹치지 않게 이 달력은 가로 월 이동만 받는다(세로 drag 는 시트 스크롤로 간다).
                  availableGestures: AvailableGestures.horizontalSwipe,
                  // [DU194 C1] 큰 글자에서 두 자리 날짜가 칸 여백 때문에 줄바뀜·잘리지 않게 이 시트만 칸 여백을 좁힌다(글자 크기 그대로, 보통 배율은 기본 여백).
                  cellMargin: MediaQuery.textScalerOf(ctx2).scale(10) > 15 ? const EdgeInsets.all(1) : null,
                  onDaySelected: (sel, foc) {
                    final selDate = DateTime.utc(sel.year, sel.month, sel.day);
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
                  // [판정286] 공고 점(eventLoader·markerBuilder)을 뺐다 — 날짜를 고르는 시트다(일정 달력 기능은 배정 0).
                  eventLoader: (_) => const [],
                  enabledDayPredicate: (day) =>
                      !DateTime.utc(day.year, day.month, day.day).isBefore(today),
                ),
                // [판정286] `공고 있음` 범례도 함께 뺐다.
                SizedBox(height: 4 * s),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }

  // ── STATE C: 통합 날짜 영역 (판정285 §3·§4) ───────────────────────
  //   띠(오늘~+6 · 날짜 선택 시트로 옮김) → 범례·날짜 선택/해제 → (미선택) 오늘 정상0 안내 | (선택) 그날 내 일정 → 그날 일자리.
  //   모든 날짜를 고를 수 있다(공고·일정·조회 결과와 무관 — C285-01). 오늘은 외곽선, 자동 선택 0.
  //   같은 날 재탭 = 선택 유지 · `날짜 해제` 로만 해제. 날짜 탭은 쓰기 0(출퇴근·지원 실행 없음) · 자동 스크롤/포커스 이동 0.
  Widget _buildHeroStateC(BuildContext context, double s, ThemeData theme) {
    final stripDays = List.generate(7, (i) => _stripStart.add(Duration(days: i)));
    final selected = _selectedDateChip;
    // [C285-03] 표시 중인 일곱 날 각각의 내 일정 — 점·범례·의미 이름이 같은 결과를 읽는다(선택일 본문도 같은 함수).
    final schedules = {
      for (final d in stripDays) DateTime.utc(d.year, d.month, d.day): _scheduleOn(DateTime.utc(d.year, d.month, d.day)),
    };
    final hasConfirmedInStrip = schedules.values.any((v) => v.confirmed.isNotEmpty);
    final hasPendingInStrip = schedules.values.any((v) => v.pending.isNotEmpty);
    // [판정286] 띠의 공고 수(`N개`) 줄·의미 이름·폭 계산을 뺐다 — 날짜 영역은 내 일정만. 공고는 바로 아래 일자리 섹션.
    const wd = ['월', '화', '수', '목', '금', '토', '일'];
    // [S080 T1 · 판정59] 오늘(KST · 주입 시계) — 오늘 칸은 미선택이면 brand 외곽선 · brand 숫자, 선택이면 기존 채움이 우선한다.
    //   범위(7일) 밖이면 표시하지 않는다(억지 노출 0). 오늘을 자동 선택하지 않는다.
    final todayKst = FormatHelper.toKstDate(_now());
    final todayKey = DateTime.utc(todayKst.year, todayKst.month, todayKst.day);

    // [CP03 Q6] 요일 12/400·숫자 15/700, 주말도 중립색. 선택 = brand 채움 + 흰 숫자, 점·조건부 `N개` 유지.
    //   각 칸 폭 ≥48 이고 실제 배율의 필요 폭만큼 늘린다. 일곱 칸이 들어가면 균등 분배, 넘치면 가로 스크롤.
    final dowStyle = const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary);
    const numStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
    final circleD = 36.0 * s;
    // [판정285 §3] 확정 = successDark · 지원 중 = warningDarkest — 옛 `이번 주 일정`·일정 달력과 같은 범례 색(새 색 0).
    Widget dot(Color c) => Container(
          width: 5 * s,
          height: 5 * s,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        );

    void selectDay(DateTime dayKey) {
      // [판정285 §4] 같은 날을 다시 눌러도 선택을 유지한다(해제는 `날짜 해제`).
      if (_selectedDateChip == dayKey) return;
      setState(() => _selectedDateChip = dayKey);
    }

    Widget cell(DateTime day) {
      final dayKey = DateTime.utc(day.year, day.month, day.day);
      final sch = schedules[dayKey]!;
      final hasConfirmed = sch.confirmed.isNotEmpty;
      final hasPending = sch.pending.isNotEmpty;
      final isSelected = selected == dayKey;
      final isToday = dayKey == todayKey;
      // [판정285 C285-01] 모든 날짜가 선택 가능 — 흐린 숫자(옛 비활성 술어)를 두지 않는다.
      final numColor = isSelected ? Colors.white : (isToday ? AppColors.brand : AppColors.textPrimary);
      final dowLabel = wd[day.weekday - 1];
      // 의미 — 전체 날짜·오늘·선택(플래그)·확정/지원 중 존재. [판정286] 공고 수는 날짜 의미에서 뺐다.
      final semLabel = [
        '${day.month}월 ${day.day}일 $dowLabel요일',
        if (isToday) '오늘', // [S080 T1] 날짜 의미에서 한 번만 구별 — 선택 플래그와 합치지 않는다
        if (hasConfirmed) '확정 근무 있음',
        if (hasPending) '지원 중 있음',
      ].join(', ');
      // [CP03 C1] 콜백 하나를 의미 노드(excludeSemantics 바깥)와 GestureDetector 가 함께 쓴다 — 모든 날짜.
      void onCellTap() => selectDay(dayKey);
      return Semantics(
        container: true,
        button: true,
        enabled: true, // [C285-01] 모든 날짜가 선택 가능 — 활성 상태를 의미에도 밝힌다
        selected: isSelected,
        label: semLabel,
        excludeSemantics: true,
        onTap: onCellTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onCellTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: ConceptSpace.minTouch, minHeight: ConceptSpace.minTouch),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(dowLabel, style: dowStyle),
                SizedBox(height: 5 * s),
                // 숫자 상자 = 최소 36*s + 내용(구현100 C100-1). 점은 상자 아래 겹쳐 그린다 — 확정·지원 중이 같은 날이면 둘 다.
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.topCenter,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      constraints: BoxConstraints(minWidth: circleD, minHeight: circleD),
                      padding: EdgeInsets.symmetric(horizontal: 2 * s),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isSelected ? AppColors.brand : Colors.transparent,
                      ),
                      // [S080 T1] 미선택 오늘 = brand 외곽선(앞면 장식 — 상자 크기 · 숫자 위치 불변)
                      foregroundDecoration: (isToday && !isSelected)
                          ? BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.brand, width: 1.5))
                          : null,
                      child: Center(
                        widthFactor: 1.0,
                        heightFactor: 1.0,
                        child: Text('${day.day}', style: numStyle.copyWith(color: numColor)),
                      ),
                    ),
                    if (hasConfirmed || hasPending)
                      Positioned(
                        bottom: -8 * s,
                        left: 0,
                        right: 0,
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          if (hasConfirmed) dot(AppColors.successDark),
                          if (hasConfirmed && hasPending) SizedBox(width: 3 * s),
                          if (hasPending) dot(AppColors.warningDarkest),
                        ]),
                      ),
                  ],
                ),
                // [판정286] 점이 상자 아래로 8*s 내려온다 — 그 자리만 남긴다(공고 수 줄 없음).
                SizedBox(height: 10 * s),
              ],
            ),
          ),
        ),
      );
    }

    // 칸 필요 폭 — 실제 배율의 숫자(두 자리)·요일·숫자 상자 중 가장 넓은 것, 최소 48.
    double cellNeed() {
      var w = ConceptSpace.minTouch;
      for (final d in stripDays) {
        final candidates = <double>[
          circleD,
          _oneLineWidth(context, '${d.day}', numStyle) + 4 * s,
          _oneLineWidth(context, wd[d.weekday - 1], dowStyle),
        ];
        for (final c in candidates) {
          if (c > w) w = c;
        }
      }
      return w;
    }

    final strip = LayoutBuilder(builder: (context, c) {
      final need = cellNeed();
      if (need * 7 <= c.maxWidth) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final d in stripDays) Expanded(child: cell(d)),
        ]);
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final d in stripDays) SizedBox(width: need, child: cell(d)),
        ]),
      );
    });

    // 범례(표시 중인 일곱 날에 실제로 있을 때만) · `날짜 선택`(시트) · `날짜 해제`(선택 중일 때만).
    //   들어가면 한 줄(양 끝), 아니면 자연 줄바꿈 — 글자 축소·말줄임 0.
    const legendStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary);
    Widget legendItem(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
          dot(c),
          const SizedBox(width: 4),
          Text(label, style: legendStyle),
        ]);
    Widget action(String label, VoidCallback onTap) => Semantics(
          // [CP03 C1] 같은 콜백을 의미 노드(독립)와 GestureDetector 에 둔다.
          container: true,
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: onTap,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: ConceptSpace.minTouch, minHeight: ConceptSpace.minTouch),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: ConceptText.count().copyWith(height: 1.3)),
                if (label == '날짜 선택') const Icon(Icons.chevron_right, size: 18, color: AppColors.brand),
              ]),
            ),
          ),
        );
    final legends = <Widget>[
      if (hasConfirmedInStrip) legendItem(AppColors.successDark, '확정 근무'),
      if (hasPendingInStrip) legendItem(AppColors.warningDarkest, '지원 중'),
    ];
    final actions = <Widget>[
      if (selected != null) action('날짜 해제', () => setState(() => _selectedDateChip = null)),
      action('날짜 선택', () => _showDatePickerSheet(context, s)),
    ];
    // 범례가 없으면 행동만 오른쪽(옛 `날짜 선택` 자리 그대로).
    final belowStrip = legends.isEmpty
        ? Align(alignment: Alignment.centerRight, child: Wrap(spacing: 8, alignment: WrapAlignment.end, children: actions))
        : Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Wrap(spacing: 12, runSpacing: 4, children: legends),
              Wrap(spacing: 8, children: actions),
            ],
          );

    // 띠가 오늘에서 옮겨 갔으면(날짜 선택 시트) 범위를 글로 밝힌다 — 월이 바뀌어도 어느 날들인지 알 수 있게.
    final stripEnd = stripDays.last;
    final moved = DateTime.utc(_stripStart.year, _stripStart.month, _stripStart.day) != todayKey;

    // 영역 키 — 시험·캡처가 이 영역만 잰다(동작 없음).
    return Column(
      key: const ValueKey('worker-home-date-area'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context, title: '날짜별 일정 · 일자리'),
        const SizedBox(height: ConceptSpace.sectionTitleToCard),
        if (moved) ...[
          Text(
            TextLayout.keepWords('${_stripStart.month}월 ${_stripStart.day}일 – ${stripEnd.month}월 ${stripEnd.day}일'),
            style: ConceptText.meta(),
          ),
          const SizedBox(height: 8),
        ],
        // 그룹 의미 — 각 날짜는 따로 읽힌다(전체 날짜·오늘·선택·확정/지원 중·일자리 수).
        Semantics(
          container: true,
          explicitChildNodes: true,
          label: '날짜별 일정과 일자리',
          child: strip,
        ),
        const SizedBox(height: 8),
        belowStrip,
        if (selected == null && _todayZeroNotice)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(TextLayout.keepWords('오늘 확정된 근무가 없어요'),
                semanticsLabel: '오늘 확정된 근무가 없어요', style: ConceptText.body(color: AppColors.textSecondary)),
          ),
        if (selected == null && _todayPartialNotice)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(TextLayout.keepWords('오늘 일정을 모두 확인하지 못했어요. 내 일정에서 확인해 주세요'),
                semanticsLabel: '오늘 일정을 모두 확인하지 못했어요. 내 일정에서 확인해 주세요',
                style: ConceptText.body(color: AppColors.textSecondary)),
          ),
        // 선택일 — 그날 내 일정(최대 2) → 그날 일자리 안내 → 「M월 D일 일자리 보기」(항상).
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: selected != null ? _selectedDayPanel(context, s, selected) : const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// [판정285 §4 B(a)] 선택일 인라인 — 「M월 D일 내 일정」 최대 2건(확정 먼저 · 시각순 · 상태/시간/사업장) ·
  ///   더 있으면 `외 N건` + 「내 일정에서 보기」. [판정286] 그날 일자리 안내·버튼은 일자리 섹션으로 옮겼다.
  ///   로딩/실패/일부만 읽음은 0 으로 말하지 않는다 — 일정 조회 상태만 말한다(공고 상태는 일자리 섹션).
  Widget _selectedDayPanel(BuildContext context, double s, DateTime day) {
    final md = '${day.month}월 ${day.day}일';
    final sch = _scheduleOn(day);
    final entries = [...sch.confirmed, ...sch.pending];
    // [PERF-P1] '불러오는 중'은 첫 1라운드 전뿐이다 — 재조회 중에는 마지막 성공 값으로 그대로 말한다.
    final appsUnknown = !_mainRoundDone || (_homeLoadFailed && _applications.isEmpty);
    final appsStale = _mainRoundDone && _homeLoadFailed && _applications.isNotEmpty;
    final appsPartial = _mainRoundDone && !_homeLoadFailed && _applicationsMaybePartial;
    final infoStyle = ConceptText.body(color: AppColors.textSecondary);

    void openSchedule() {
      final scope = UserTabScope.of(context);
      // [판정285 §4] 선택일의 월·날짜·당일 목록 + 상태 필터 ALL 로 — 홈 Navigator 에 일정 화면을 쌓지 않는다(탭 전환).
      final go = scope?.switchToScheduleDate;
      if (go != null) {
        go(day);
      } else {
        scope?.switchToTab(2);
      }
    }

    Widget link(String label) => Semantics(
          container: true,
          button: true,
          label: label,
          excludeSemantics: true,
          onTap: openSchedule,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: openSchedule,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: ConceptSpace.minTouch, minHeight: ConceptSpace.minTouch),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(child: Text(TextLayout.keepWords(label), style: ConceptText.count().copyWith(height: 1.3))),
                const Icon(Icons.chevron_right, size: 18, color: AppColors.brand),
              ]),
            ),
          ),
        );

    String statusOf(ApplicationModel a) => switch (a.status) {
          AppStatus.confirmed => '확정',
          AppStatus.contractPending => '계약 진행 중',
          _ => '지원 중',
        };
    Widget entry(ApplicationModel a) {
      final isPending = a.status == AppStatus.pending;
      final time = (a.startTime.isNotEmpty && a.endTime.isNotEmpty) ? '${a.startTime}–${a.endTime}' : null;
      final place = [
        if (a.businessName.isNotEmpty) a.businessName,
        if (a.selectedWorkType.isNotEmpty) a.selectedWorkType,
      ].join(' · ');
      final status = statusOf(a);
      return Semantics(
        container: true,
        label: [status, if (time != null) time, if (place.isNotEmpty) place].join(', '),
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: EdgeInsets.only(top: 7 * s, right: 8),
              child: Container(
                width: 6 * s,
                height: 6 * s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isPending ? AppColors.warningDarkest : AppColors.successDark,
                ),
              ),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  TextLayout.keepWords([status, if (time != null) time].join(' · ')),
                  style: ConceptText.body().copyWith(fontWeight: FontWeight.w700),
                ),
                if (place.isNotEmpty)
                  Text(TextLayout.keepWords(place), style: ConceptText.body(color: AppColors.textSecondary)),
              ]),
            ),
          ]),
        ),
      );
    }

    final children = <Widget>[
      Text(TextLayout.keepWords('$md 내 일정'), semanticsLabel: '$md 내 일정', style: ConceptText.taskTitle()),
    ];
    if (appsUnknown) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          TextLayout.keepWords(!_mainRoundDone ? '일정을 불러오고 있어요' : '일정을 확인하지 못했어요. 내 일정에서 확인해 주세요'),
          style: infoStyle,
        ),
      ));
      if (_mainRoundDone) children.add(link('내 일정에서 보기'));
    } else {
      if (entries.isEmpty && (appsStale || appsPartial)) {
        // [판정287 C287-01] 일부만 읽음(200 건 상한) · 이전 목록 잔존(재조회 실패)에서 그날 0 은 '없다'가 아니라 '모른다'.
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(TextLayout.keepWords('이 날짜의 일정을 모두 확인하지 못했어요. 내 일정에서 확인해 주세요'), style: infoStyle),
        ));
      } else if (entries.isEmpty) {
        // 정상 조회 · 전량(상한 미만)일 때만 정상 0 을 말한다.
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(TextLayout.keepWords('이 날짜의 확정 근무나 지원 중인 일정이 없어요'), style: infoStyle),
        ));
      } else {
        for (final a in entries.take(2)) {
          children.add(entry(a));
        }
        if (entries.length > 2) {
          children.add(Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('외 ${entries.length - 2}건', style: infoStyle),
          ));
        }
      }
      // 읽은 일정이 있을 때만 최신/일부 고지를 덧붙인다(그날 0 이면 위 미확인 안내가 이미 말했다).
      if (entries.isNotEmpty && (appsStale || appsPartial)) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            TextLayout.keepWords(appsStale
                ? '최신 일정이 아닐 수 있어요. 내 일정에서 확인해 주세요'
                : '일부 일정만 보여요. 내 일정에서 모두 확인해 주세요'),
            style: infoStyle,
          ),
        ));
      }
      if (entries.isNotEmpty || appsStale || appsPartial) children.add(link('내 일정에서 보기'));
    }

    // [판정286] 그날 일자리 안내·「M월 D일 일자리 보기」는 바로 아래 일자리 섹션 한 곳으로 옮겼다(날짜 영역 = 내 일정만).
    return Padding(
      padding: const EdgeInsets.only(top: ConceptSpace.infoGroupGap),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  // ── 지원 현황 (시안 .sec 지원현황) ──────────────────────────────
  /// [PREDEVICE-WORKER-ERROR-NOT-ZERO] ERROR — 0건이 아니라 모르는 상태.
  /// [E1-HOME-FIRST-ENTRY] 아직 읽지 않았다 — 자리를 지키되 숫자를 말하지 않는다.
  ///
  ///   `_buildPriorityCard` 의 로딩 skeleton 과 같은 관용구다(회색 블록).
  ///   문구를 쓰지 않는 이유: "불러오는 중" 도 하나의 주장인데, 이 창은
  ///   보통 1 초 미만이라 깜빡임만 남는다.
  Widget _applicationStatusSkeleton(double s) {
    return Container(
      width: double.infinity,
      height: 92 * s,
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _applicationStatusErrorCard(double s) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 24 * s, horizontal: 16 * s),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, color: AppColors.textHint, size: 32 * s),
          SizedBox(height: 8 * s),
          Text(
            '지원 현황을 불러오지 못했어요',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4 * s),
          Text(
            // [DU472] B(320 · 2.0)에서 '주세 / 요'로 끊겼다 — 낱말 사이에서만 줄바꿈(읽기는 원문).
            TextLayout.keepWords('잠시 후 다시 시도해 주세요'),
            semanticsLabel: '잠시 후 다시 시도해 주세요',
            // [DU470] textHint(grey400 · 1.88) → textTertiary(보조 안내 · 화면 바탕 위 4.90).
            style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4 * s),
          // [CP03] 실제 재조회 행동 — receiver 최소 48(정밀 §8). 문구·목적지(_loadHomeData) 그대로.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _loadHomeData,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: ConceptSpace.minTouch, minHeight: ConceptSpace.minTouch),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // [DU306 §12.2] 재시도 = 일반 진행 행동 → brand(infoDark 대신). receiver 48·목적지 그대로.
                Text(
                  '다시 시도',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                  ),
                ),
                SizedBox(width: 3 * s),
                Icon(Icons.refresh_rounded,
                    size: 15 * s, color: AppColors.brand),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// [PREDEVICE-WORKER-ERROR-NOT-ZERO] PARTIAL — 보여 주는 값이 최신이 아니다.
  // [DU306 Standards §12.2] 부분 실패(이전 값 표시) = 작은 주의 표시 + 중립 설명 + brand 재시도.
  //   주황 바탕(warning .10)·주황 `다시 시도`(흰 바탕 대비 낮음)를 걷고 중립 바탕(background)으로 낮춘다.
  //   주의 아이콘(warning)은 작은 상태 표시로 남긴다. 띠 전체 탭 receiver 최소 48(글자 확대 시 자연 높이).
  Widget _staleNotice(double s) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _loadHomeData,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: ConceptSpace.minTouch),
        padding: EdgeInsets.symmetric(vertical: 9 * s, horizontal: 12 * s),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(Icons.cloud_off_rounded, size: 15 * s, color: AppColors.warning),
          SizedBox(width: 7 * s),
          const Expanded(
            child: Text(
              '최신 정보를 불러오지 못해 이전 내용을 보여드려요',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          SizedBox(width: 6 * s),
          Text(
            '다시 시도',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.brand,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildApplicationStatus(BuildContext context, double s) {
    // 3-column 통계
    final pendingCount = _cachedPendingCount;
    final confirmedCount = _cachedConfirmedCount;
    final resultWaitCount = _cachedContractPendingCount;
    // 최근 2건 지원서
    final recent = _cachedRecentApplications.take(2).toList();

    return Container(
      color: Colors.white,
      // [CP03 Q9] 좌우 화면 여백만 — 섹션 사이 24 는 본문 리듬이 맡는다.
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더 — `내 지원 현황` + `전체 보기`(꺾쇠 아이콘 1개, receiver 48). 목적지 그대로.
          _sectionHeader(
            context,
            title: '내 지원 현황',
            actionText: '전체 보기',
            onAction: () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => const MyApplicationsScreen())),
          ),
          const SizedBox(height: ConceptSpace.sectionTitleToCard),
          // [PREDEVICE-WORKER-ERROR-NOT-ZERO] ERROR를 먼저 가른다.
          //   조회에 실패하고 보여 줄 것이 하나도 없을 때 "아직 지원한 일자리가
          //   없어요"라고 말하면 거짓말이 된다. 0건이 아니라 모르는 상태다.
          // [E1-HOME-FIRST-ENTRY] LOADING 을 **먼저** 가른다.
          //   예전에는 `_isLoadingData` 가 true 여도 들고 있는 지원서가
          //   없으면 아래 `else` 로 떨어져 `검토중 0 · 확정 0` 을 자신 있게
          //   그렸다. 아직 읽지 않은 것은 0 건이 아니다.
          if (_isLoadingData && _applications.isEmpty) ...[
            _applicationStatusSkeleton(s),
          ] else if (_homeLoadFailed && _applications.isEmpty && !_isLoadingData) ...[
            _applicationStatusErrorCard(s),
          ] else if (_applications.isEmpty && !_isLoadingData) ...[
            Container(
              width: double.infinity,
              // [DU1 구현98] 아래 여백 24 → 10: 링크 receiver(48)의 아래 여유가 시각 여백을 대신한다(위 주석).
              padding: EdgeInsets.fromLTRB(16 * s, 24 * s, 16 * s, 10 * s),
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
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center),
                  SizedBox(height: 4 * s),
                  // [DU1 구현98 S080 V6·V9] 설명 textHint(#BDBDBD, 화면 바탕 1.75:1 — 실측) → textSecondary.
                  //   탐색 링크 infoDark(#1976D2, 4.30:1) → 같은 홈의 다른 링크(`날짜 더보기`·`전체보기`)와 같은 brand.
                  //   링크 문구·목적지(일자리 탭)·행동 있는 빈 안내라는 역할은 그대로다.
                  Text('원하는 날짜의 일자리를 찾아보세요',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center),
                  // [DU1 구현98 S080 R] 링크의 실제 receiver 가 글자 높이뿐이었다(실측 105.2×19.0) → 바깥 receiver 높이 48.
                  //   보이는 글자 위치가 거의 그대로이도록 위 간격 14 → 4, 카드 아래 안쪽 여백 24 → 10 으로 receiver 의
                  //   위아래 여유(각 ~14.5)를 흡수한다. 목적지·문구·누르는 동작은 그대로다.
                  SizedBox(height: 4 * s),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => UserTabScope.of(context)?.switchToTab(1),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('일자리 찾기',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brand,
                            )),
                        SizedBox(width: 3 * s),
                        Icon(Icons.arrow_forward_rounded,
                            size: 15 * s, color: AppColors.brand),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
          // PARTIAL — 직전 데이터는 있으나 마지막 조회가 실패했다.
          //   숫자를 지우면 실수입/지원이 사라진 것처럼 보이므로 그대로 두되,
          //   지금 보는 것이 최신이 아닐 수 있다는 사실을 함께 말한다.
          if (_homeLoadFailed) ...[
            _staleNotice(s),
            SizedBox(height: 10 * s),
          ],
          // 3열 통계 (시안 .app-summary) — [CP03 Q9] 지원 현황 3칸 요약만 conceptRaised(한 겹). 집계·분기 그대로.
          Container(
            decoration: ConceptSurface.raised(),
            padding: EdgeInsets.symmetric(vertical: 12 * s),
            // [DU424 V-c] 세 칸 숫자의 윗선을 맞춘다 — 기본 가운데 정렬이면 라벨이 두 줄인 칸(계약 대기 · 큰 글자)만
            //   숫자가 위로 밀렸다(B 320×640@2.0 에서 17px). 라벨 · 숫자 · 집계 · 구분선 크기는 그대로다.
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _statCell(s, '$pendingCount', '검토 중', null),
              Container(width: 1, height: 36 * s, color: AppColors.borderLight),
              _statCell(s, '$confirmedCount', '확정', AppColors.successDark),
              Container(width: 1, height: 36 * s, color: AppColors.borderLight),
              _statCell(s, '$resultWaitCount', '계약 대기', AppColors.warningDark),
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
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.work_outline_rounded,
                            color: AppColors.textSecondary, size: 18 * s),
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
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: 1 * s),
                            // [DU194 C4] 날짜·시작/종료 시각 전문 — 말줄임 없이 날짜 뒤와 '–' 뒤에서만 줄바꿈(보이는 글자는 같다)
                            Text(
                              hasTime
                                  ? '${TextLayout.keepWords(FormatHelper.formatDateCompact(app.workDate))}  ${TextLayout.unit('${app.startTime} –')} ${TextLayout.unit(app.endTime)}'
                                  : TextLayout.keepWords(FormatHelper.formatDateCompact(app.workDate)),
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
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
                              fontSize: 12,
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
            style: AppTextStyles.statNumber(color: color)),
        SizedBox(height: 2 * s),
        Text(TextLayout.keepWords(label),
            semanticsLabel: label,
            textAlign: TextAlign.center,
            style: AppTextStyles.statLabel()),
      ]),
    );
  }

  // ── 수입 현황 — 이번 달 compact (섹션 → IncomeDetailScreen) ──────────
  Widget _buildIncomeSection(BuildContext context, double s, ThemeData theme) {
    // [R7-P2-1 최종] '이번 달'의 기준은 **KST 달력월**이다.
    //   원장(`getMyMonthlyAttendances`)은 서버가 KST 로 잘라 준다. 여기서
    //   기기 로컬 연·월을 쓰면 비-KST 기기에서 라벨과 금액이 **다른 달**을
    //   말하고, KST 1일에 일한 돈이 이번 달에서 빠진다.
    final now = FormatHelper.toKstDate(_now());
    final monthApps = CalendarHelper.getThisMonthApplications(_applications, now);

    // 근무 완료: 관리자가 임금 확정/지급 처리한 금액 (attendance.finalWage)
    final wageCompleted = CalendarHelper.getConfirmedIncome(_attendances, now);

    // 근무 예정: 이번 달 확정 지원서 중 아직 벌 예정인 것 (시급 환산 포함)
    // [PREDEVICE-INCOME-NOSHOW] 미출근 여부만 보면 NO_SHOW·결근이 계속
    //   "벌 예정"으로 남는다 — 그 날은 벌 돈이 0으로 이미 마감됐다.
    //   판정은 CalendarHelper.isScheduledIncome 한 곳에 있다.
    // [AUD-3 M3 · 판정293 §6] 근무 1회 금액은 하루 예상 helper 와 같은 계산(CalendarHelper.expectedShiftWage —
    //   약속 휴게 차감 · 종료=시작/휴게 모름 = 계산 불가 · 월급·유형 모름은 근무 1회 금액 없음). 계산할 수 없는 근무는
    //   합계에 0 으로 넣지 않고 '금액 확인 필요 N건' 으로 따로 말한다.
    var wageScheduled = 0;
    var scheduledUnknown = 0;
    for (final a in monthApps
        .where((a) => AppStatus.confirmedStatuses.contains(a.status))
        .where((a) =>
            CalendarHelper.isScheduledIncome(a, _attendances, now: _now()))) {
      final w = CalendarHelper.expectedShiftWage(a);
      if (w == null) {
        scheduledUnknown++;
      } else {
        wageScheduled += w;
      }
    }

    // 일했지만 금액이 아직 확정되지 않은 근무 — 어느 합계에도 더하지 않는다.
    final settlementPending =
        CalendarHelper.settlementPendingCount(_attendances, now);

    final wageTotal = wageCompleted + wageScheduled;

    return Container(
      color: Colors.white,
      // [CP03 Q9] 좌우 화면 여백만 — 섹션 사이 24 는 본문 리듬이 맡는다.
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더 — 대상 월 행동 `{년}년 {월}월` + 꺾쇠 아이콘 1개(문자열 `›` 삭제). 목적지·대상 월 그대로.
          _sectionHeader(
            context,
            title: '수입 현황',
            actionText: '${TextLayout.keepWords('${now.year}년')} ${TextLayout.unit('${now.month}월')}', // [DU203 C201-2] 연/월 사이만 줄바꿈
            actionLabel: '${now.year}년 ${now.month}월',
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
          const SizedBox(height: ConceptSpace.sectionTitleToCard),
          // 신규 사용자 Empty State — 수입 기록 없음
          // [R7-P2-1 후속 P21-E] 근태를 못 읽었으면 "수입이 없다"고 말할 수
          //   없다 — 0원은 조회 성공일 때만 쓸 수 있는 말이다.
          if (!_isLoadingData &&
              !_attendancesFailed &&
              wageCompleted == 0 &&
              wageScheduled == 0 &&
              scheduledUnknown == 0)
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
                  Text(TextLayout.keepWords('아직 표시할 수입 금액이 없어요'), // [DU203 C201-3] '없어요' 등 낱말 안 분절 0
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center),
                  SizedBox(height: 3 * s),
                  // [DU1 구현99 C99-1] 읽어야 하는 안내 — textHint(#BDBDBD, 화면 바탕 1.754:1 실측) → textSecondary.
                  // [DU398 후보] 낱말 안 줄바꿈 0 — 제목과 같은 keepWords, 읽기 이름 원문(B320@2.0 '수 / 입' 분절, DU397 관측)
                  Text(TextLayout.keepWords('확정 금액과 근무 예정 수입이 여기에 표시돼요'),
                      semanticsLabel: '확정 금액과 근무 예정 수입이 여기에 표시돼요',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                    value: _isLoadingData
                        ? null
                        : (_attendancesFailed
                            ? '확인 못함'
                            : FormatHelper.formatWage(wageCompleted)),
                    valueColor: (!_attendancesFailed && wageCompleted > 0)
                        ? AppColors.successDark
                        : AppColors.textSecondary,
                    valueBold: false,
                  ),
                  // ── 근무 예정 행 — 확정된 미출근 근무의 예상 수입 ────────
                  SizedBox(height: 8 * s),
                  _incomeRow(
                    s: s,
                    label: '근무 예정',
                    labelColor: AppColors.textSecondary,
                    // [AUD-3 M3 · 판정296] 계산할 수 없는 근무가 있으면 부분합·0원을 전체처럼 말하지 않는다.
                    value: _isLoadingData ? null : ExpectedWageText.partialTotal(wageScheduled, scheduledUnknown),
                    valueColor: AppColors.textPrimary,
                    valueBold: false,
                  ),
                  // ── 금액 확인 필요 행 — 근무 예정이지만 예상 금액을 계산할 수 없는 근무 [AUD-3 M3] ──
                  if (!_isLoadingData && scheduledUnknown > 0) ...[
                    SizedBox(height: 8 * s),
                    _incomeRow(
                      s: s,
                      label: '금액 확인 필요',
                      labelColor: AppColors.textSecondary,
                      value: '$scheduledUnknown건',
                      valueColor: AppColors.textPrimary,
                      valueBold: false,
                    ),
                  ],
                  // ── 정산 중 행 — 일했지만 금액이 아직 확정되지 않은 근무 ──
                  // [PREDEVICE-PENDING-WAGE-VISIBILITY] 그 날은 출근했으므로
                  //   근무 예정에서 빠지고, 아직 확정 전이라 근무 완료에도 들어
                  //   가지 않는다. 두 합계 어디에도 없으면 일한 하루가 사라진
                  //   것처럼 보인다. 확정 전 금액을 확정 금액인 양 더하지 않고
                  //   건수만 말한다. 0건이면 줄을 만들지 않는다.
                  if (!_isLoadingData && settlementPending > 0) ...[
                    SizedBox(height: 8 * s),
                    _incomeRow(
                      s: s,
                      label: '정산 중',
                      labelColor: AppColors.textSecondary,
                      value: '$settlementPending건',
                      // [DU595b · 판정139 §3 :42 PP-STATUS-PAIR] '정산 중' 건수 = C2 중립 집계(일반값 textPrimary · 같은 표 '근무 예정' 값과 같다) — 경고 아님.
                      valueColor: AppColors.textPrimary,
                      valueBold: false,
                    ),
                  ],
                  SizedBox(height: 12 * s),
                  Divider(height: 1, color: AppColors.borderLight),
                  SizedBox(height: 12 * s),
                  // ── 예상 수입 합계 ────────────────────────────────────
                  // 합계는 확정 부분을 모르면 만들 수 없다 — 반쪽을 총액이라
                  //   부르지 않는다.
                  _incomeRow(
                    s: s,
                    label: '예상 수입',
                    labelColor: AppColors.brand,
                    value: _isLoadingData
                        ? null
                        : (_attendancesFailed
                            ? '확인 못함'
                            : ExpectedWageText.partialTotal(wageTotal, scheduledUnknown)),
                    valueColor: AppColors.brand,
                    valueBold: true,
                  ),
                  if (_attendancesFailed) ...[
                    SizedBox(height: 10 * s),
                    // [DU306 §12.2·§12.3] 재시도 링크 = brand(infoDark 대신), 실제 receiver 최소 높이 48(글자 밖 빈 곳도 탭).
                    //   문구·목적지·로딩 중 비활성은 그대로다.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _isLoadingData ? null : () => _loadHomeData(),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: ConceptSpace.minTouch),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.cloud_off_rounded,
                              size: 14 * s, color: AppColors.textSecondary),
                          SizedBox(width: 5 * s),
                          Flexible(
                            child: Text('이번 달 근무 기록을 불러오지 못했어요 · 다시 시도',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brand,
                                )),
                          ),
                        ]),
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


  // ── [DS-03] 신분증 열람 요청 진입점 ────────────────────────────
  /// 처리 대기 중인 신분증 열람 요청이 있을 때만 표시하는 Compact Card.
  ///
  /// - 표시 판단: 요청 컬렉션 조회 결과 (notification 무관)
  /// - 홈이 담당하는 것: 발견 + 진입. 승인·거절·요청 목록은 다이얼로그가 처리
  /// - 0건이 되면 자동 소멸
  ///
  /// 지원 준비 카드보다 강한 색을 쓰되 경고색(빨강)은 쓰지 않는다.
  /// 사용자 잘못이 아니라 상대방이 보낸 처리 대기 건이다.
  /// [PII-DOC-R1.6.1] 서류 보완 할 일 카드.
  ///
  ///   source는 서버의 OPEN correction이다. 알림이 아니다 — 알림을 읽거나
  ///   지워도 할 일은 남고, 실제로 서류가 해결돼야 사라진다.
  ///
  ///   지급이 막힌 건은 이미 일한 대가가 멈춰 있다는 뜻이므로 가장 먼저
  ///   보여준다. 금액이 사라진 것은 아니라는 말도 함께 한다.
  /// [RENEWAL-PROPOSAL-COMMITMENT] 연장 제안 할 일 카드.
  ///
  ///   source 는 알림이 아니라 제안 문서다. 알림을 읽거나 지워도, 앱을
  ///   다시 켜도 수락/거절하기 전까지 이 카드는 남는다.
  Widget _buildRenewalProposalCard(BuildContext context, double s) {
    if (!_zoneRevealed) return const SizedBox.shrink(); // [PERF-P1]
    if (!_renewalProposalsLoaded) return const SizedBox.shrink();
    if (_renewalProposals.isEmpty) return const SizedBox.shrink();
    final first = _renewalProposals.first;
    final more = _renewalProposals.length - 1;
    // [DU306 Standards §12.2] 연장 제안은 '확정·달성'이 아니라 근로자 응답을 기다리는 요청이다 —
    //   녹색(success) 대신 같은 홈의 기다리는 요청 카드(신분증 열람·초대)와 같은 brand 한 겹.
    const accent = AppColors.brand;
    final start = FormatHelper.toKstDate(first.effectiveStart);
    final end = FormatHelper.toKstDate(first.effectiveEnd);
    final title = more > 0 ? '계약 연장 제안 ${more + 1}건' : '계약 연장 제안';
    final subtitle = '${first.businessName} · '
        '${start.month}/${start.day}~${end.month}/${end.day}';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)), // [CP03 Q9] 간격은 본문 리듬
      child: GestureDetector(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  RenewalProposalScreen(focusProposalId: first.id),
            ),
          );
          if (mounted) _loadHomeData();
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.30)),
          ),
          // [DU306 §12.3] 제목 1줄·부제 2줄 말줄임 제거 — 사업장 이름·연장 기간은 잘리면 다른 제안으로 읽힌다.
          //   같은 홈의 필수응답 카드와 같은 공용 배치(_taskCardRow): 제목은 낱말, 부제는 구분점 조각 사이에서만
          //   줄을 바꾸고, 본문 폭이 모자라면 `확인하기`를 아래 오른쪽 줄로 내린다(카드 전체 탭·목적지 그대로).
          child: _taskCardRow(
            context,
            s,
            icon: Container(
              width: 38 * s,
              height: 38 * s,
              decoration:
                  const BoxDecoration(color: accent, shape: BoxShape.circle),
              child: Icon(Icons.autorenew,
                  size: 20 * s, color: Colors.white),
            ),
            iconWidth: 38 * s,
            title: title,
            titleDisplay: TextLayout.keepWords(title),
            titleStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            subtitle: subtitle,
            subtitleDisplay: TextLayout.phrases(subtitle),
            subtitleStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            actionText: '확인하기',
            actionStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: accent),
          ),
        ),
      ),
    );
  }

  /// [R7-P2-1 후속 H6-E] 서류 보완 **확인 실패** 표면.
  ///
  ///   있는지 없는지 모른다고만 말한다 — pending Task 를 지어내지 않는다.
  ///   다른 여섯 읽기와 확정 근무·수입 카드는 건드리지 않는다(홈 전체를
  ///   오류 페이지로 바꾸지 않는다).
  Widget _buildCorrectionFailureCard(BuildContext context, double s) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)), // [CP03 Q9] 간격은 본문 리듬
      // [DU306 §12.3] `다시 시도` 글자 receiver 가 약 30 높이였다 — 같은 홈의 다른 조회 실패 카드(미퇴근·계약해지)처럼
      //   카드 전체를 같은 재조회(_reloadCorrections, 이 읽기 하나만)로 누르게 한다. 진행 중에는 둘 다 비활성.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _isReloadingCorrections ? null : _reloadCorrections,
        child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded,
                color: AppColors.textHint, size: 22 * s),
            SizedBox(width: 12 * s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('서류 요청을 확인하지 못했어요',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      )),
                  SizedBox(height: 2 * s),
                  Text('요청이 없다는 뜻은 아니에요',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      )),
                ],
              ),
            ),
            SizedBox(width: 8 * s),
            // 이 읽기 하나만 다시 부른다 — 홈 전체를 다시 읽지 않는다.
            GestureDetector(
              onTap: _isReloadingCorrections ? null : _reloadCorrections,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: 8 * s, vertical: 6 * s),
                child: Text(
                  _isReloadingCorrections ? '확인 중' : '다시 시도',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand, // [DU306 §12.2] 재시도 = brand(infoDark 대신)
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// 재시도 — **탭으로만** 다시 읽는다. polling·listener 를 만들지 않는다.
  Future<void> _reloadCorrections() async {
    if (_isReloadingCorrections) return;
    final uid = context.read<UserProvider>().currentUser?.uid;
    setState(() => _isReloadingCorrections = true);
    try {
      final s = await _reads.documentCorrections();
      if (!mounted) return;
      // 계정이 바뀐 뒤 늦게 온 응답을 새 화면에 얹지 않는다.
      if (context.read<UserProvider>().currentUser?.uid != uid) return;
      setState(() {
        _correctionSurface = s;
        _correctionsLoaded = true;
      });
    } finally {
      if (mounted) setState(() => _isReloadingCorrections = false);
    }
  }

  Widget _buildCorrectionTaskCard(BuildContext context, double s) {
    if (!_zoneRevealed) return const SizedBox.shrink(); // [PERF-P1]
    if (!_correctionsLoaded) return const SizedBox.shrink();
    // [R7-P2-1 후속 H6-E] 조회 실패는 "할 일 없음"이 아니다.
    //
    //   전에는 카드를 숨기고 다음 조회를 기다렸다. 거짓말은 아니었지만
    //   **아무 말도 하지 않았다** — 요청이 있는지 모르는 상태와 없는 상태가
    //   화면에서 같아진다. 그리고 이 요청을 다시 보여주는 다른 화면이 없다:
    //   내 서류 화면은 보완 요청을 읽지 않는다(grep 0건). 즉 실패하면
    //   사용자는 어디서도 단서를 못 받고 다시 시도할 방법도 없었다.
    //
    //   그래서 **없는 할 일을 지어내지 않으면서** 확인에 실패했다고 말하고
    //   다시 시도를 준다. 문구·아이콘은 홈의 기존 실패 어휘를 쓴다.
    if (_correctionSurface.loadFailed) {
      return _buildCorrectionFailureCard(context, s);
    }
    final task = _correctionSurface.primary;
    if (task == null) return const SizedBox.shrink();

    final more = _correctionSurface.tasks.length - 1;
    final subtitle = more > 0 ? '${task.subtitleFor()} · 외 $more건' : task.subtitleFor();
    const accent = AppColors.warning;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)), // [CP03 Q9] 간격은 본문 리듬
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => const DocumentManagementScreen()),
        ),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.30)),
          ),
          // [DU595c · 판정114 §6 :99 · 판정177 §6] 제목 · 부제 말줄임(2줄) 제거 — 같은 홈의 필수응답 카드와 같은 공용 배치(_taskCardRow): 제목은 낱말,
          //   부제는 구분점 조각 사이에서만 줄을 바꾸고 본문 폭이 모자라면 `등록하기`를 아래 오른쪽 줄로(카드 전체 탭 · 목적지 · 표시 조건 그대로).
          //   원 아이콘 = warning 의 진한 짝(warningDark 면 · 흰 글리프 · DU595b J084b 그대로) · 카드 면 · 테두리는 accent(warning) 그대로.
          child: _taskCardRow(
            context,
            s,
            icon: Container(
              width: 38 * s,
              height: 38 * s,
              decoration: const BoxDecoration(
                  color: AppColors.warningDark, shape: BoxShape.circle),
              child: Icon(Icons.assignment_late_outlined,
                  size: 20 * s, color: Colors.white),
            ),
            iconWidth: 38 * s,
            title: task.title,
            titleDisplay: TextLayout.keepWords(task.title),
            titleStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            subtitle: subtitle,
            subtitleDisplay: TextLayout.phrases(subtitle),
            subtitleStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            // [DU476] 급여 안내 textTertiary · 행동 글자 · 화살표 warningDark — 값 그대로.
            note: task.isPayroll ? '확정된 급여 금액은 그대로 유지돼요' : null,
            noteStyle: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
            actionText: '등록하기',
            actionStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.brand,
            ),
            actionTrailing: Icon(Icons.chevron_right, color: AppColors.brand, size: 20 * s),
            actionTrailingWidth: 20 * s,
          ),
        ),
      ),
    );
  }

  Widget _buildIdRequestCard(BuildContext context, double s, UserProvider up) {
    if (!_zoneRevealed) return const SizedBox.shrink(); // [PERF-P1]
    // LOADING: 첫 조회 전에는 자리 차지 없음
    if (!_idRequestsLoaded) return const SizedBox.shrink();
    // EMPTY (조회 실패 포함): 노출 없음
    if (!_idRequestSurface.isVisible) return const SizedBox.shrink();
    final uid = up.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final accent = theme.primaryColor;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)), // [CP03 Q9] 간격은 본문 리듬
      child: GestureDetector(
        onTap: () => _openMyRequests(uid),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.32)),
          ),
          // [CP03 C1] 제목 말줄임(2줄) 제거 — 제목·부제 전문·자연 높이, 낱말 사이에서만 줄바꿈.
          //   본문 폭이 모자라면 `요청 확인`을 아래 오른쪽 줄로(카드 전체 탭·목적지 그대로).
          child: _taskCardRow(
            context,
            s,
            // 채워진 아이콘 배지 — 지원 준비 카드(연한 배지)보다 한 단계 강하게
            icon: Container(
              width: 38 * s,
              height: 38 * s,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: Icon(Icons.badge_outlined, size: 20 * s, color: Colors.white),
            ),
            iconWidth: 38 * s,
            title: _idRequestSurface.title,
            titleDisplay: TextLayout.keepWords(_idRequestSurface.title),
            titleStyle: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            subtitle: _idRequestSurface.subtitle,
            subtitleDisplay: TextLayout.keepWords(_idRequestSurface.subtitle),
            subtitleStyle: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            actionText: '요청 확인',
            actionStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
            actionTrailing: Icon(Icons.chevron_right, color: accent, size: 20 * s),
            actionTrailingWidth: 20 * s,
          ),
        ),
      ),
    );
  }

  // ── 계약해지 응답 카드 ──────────────────────────────────────
  //
  // [BLOCKER-TERMINATION-REQUEST-NO-WORKER-TASK]
  //
  //   관리자가 계약해지를 요청하면 승인·거절할 사람은 근로자다. 그런데
  //   홈에는 그 일이 없었고 알림 하나가 유일한 경로였다. 알림을 읽거나
  //   지우면 길이 사라지는데 요청은 D+3 에 자동 승인된다 — 자기 고용이
  //   끝나는 일에 대한 동의가 알림 수명에 묶여 있었다.
  //
  //   `Notification ≠ Task`: 이 카드는 canonical 도메인 상태
  //   (terminationStatus == PENDING) 에서만 파생된다.
  //
  //   신분증 열람 요청 카드와 합치지 않는다 — 정보 제공 동의와 고용 종료
  //   동의는 같은 사건이 아니다.
  Widget _buildTerminationRequestCard(
      BuildContext context, double s, UserProvider up) {
    // LOADING: 첫 조회 전에는 자리 차지 없음 · [PERF-P1] 재조회 중에는 마지막 값 유지 · 첫 표시 전 숨김
    if (!_zoneRevealed || !_mainRoundDone) return const SizedBox.shrink();
    final uid = up.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    final surface = PendingTerminationSurface.from(
      _applications,
      available: !_homeLoadFailed,
    );

    // [ERROR ≠ EMPTY] 확인하지 못한 것을 "요청 없음"으로 접지 않는다.
    //   응답하지 않으면 자동 승인되는 일이라 침묵이 가장 위험하다.
    if (surface.isUnavailable) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: _gutter(context)), // [CP03 Q9] 간격은 본문 리듬
        child: GestureDetector(
          onTap: _isLoadingData ? null : () => _loadHomeData(),
          child: Container(
            padding:
                EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Row(children: [
              Icon(Icons.cloud_off_outlined,
                  size: 20 * s, color: AppColors.textSecondary),
              SizedBox(width: 10 * s),
              Expanded(
                child: Text(
                  '계약해지 요청을 확인하지 못했어요',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              // [DU306 §12.2] 재시도 = 일반 진행 행동 → brand(예전 파랑 infoDark #1976D2 대신). 카드 전체 탭·목적지 그대로.
              Text('다시 시도',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand,
                  )),
            ]),
          ),
        ),
      );
    }

    if (!surface.isVisible) return const SizedBox.shrink();

    // 고용이 끝나는 일이다 — 신분증 요청보다 한 단계 강한 색을 쓴다.
    const accent = AppColors.error;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)), // [CP03 Q9] 간격은 본문 리듬
      child: GestureDetector(
        onTap: () => _openMyRequests(uid),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.32)),
          ),
          child: Row(
            children: [
              Container(
                width: 38 * s,
                height: 38 * s,
                decoration:
                    const BoxDecoration(color: accent, shape: BoxShape.circle),
                child: Icon(Icons.event_busy_outlined,
                    size: 20 * s, color: Colors.white),
              ),
              SizedBox(width: 12 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      surface.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 3 * s),
                    Text(
                      surface.subtitle,
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8 * s),
              Text('요청 확인',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  )),
              Icon(Icons.chevron_right, color: accent, size: 20 * s),
            ],
          ),
        ),
      ),
    );
  }

  // ── 온보딩 배너 ─────────────────────────────────────────────
  /// 지원 준비 Compact Card — APPLICANT ONBOARDING READINESS
  ///
  /// [PII-DOC-R1.5.4] ① 신분 확인 · ② 급여정보 두 항목으로 복구.
  ///
  ///   ALfit은 가입을 가볍게 두는 대신 지원 전에 기본자료를 갖추게 한다.
  ///   그래서 이 둘은 실제로 지원을 막는 항목이고, Home에 있어야 한다.
  ///
  ///   묻는 것은 등록 여부뿐이다 — 관리자 검수 상태(writer 없는
  ///   bankVerificationStatus)는 읽지 않는다. 지급 시점의 유효성은
  ///   R1.6 Payroll Readiness가 따로 판단한다.
  ///
  /// 날짜 Hero보다 시각적 우선순위가 낮은 Compact 스타일.
  /// 탭 → DocumentManagementScreen (내 서류 관리)
  /// [대표 결정 2026-11-25] 오늘의 약속 · 새 확정 근무 Hero 가 있는가 — 있으면 「시작 준비」를 그 아래에 둔다.
  bool get _hasPromiseHero => _heroTodayApp != null || _heroNewConfirmApp != null;

  Widget _buildReadinessCard(BuildContext context, double s, UserProvider up) {
    final user = up.currentUser;
    if (user == null) return const SizedBox.shrink();

    // [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 대표 결정 2026-11-25] 「시작 준비」 — 일할 지역 → 신분증/외국인등록증 →
    //   급여 계좌·통장사본. 가입 때 묻지 않은 것을 홈에서 단계별로 안내한다. 지원 시점의 서버 gate·사전 안내는 그대로.
    //   판정은 기존 값 그대로(새 판정 0): 지역 = homeRegion 존재 · 신분 = hasIdDocument ·
    //   급여 = 계좌 3필드 + 통장사본 등록 여부(presence only — 검수 상태는 읽지 않는다).
    // ⓪ 일할 지역: 가입 때 묻지 않는다(지역 gate 제거). 없으면 일자리는 전체 지역으로 보인다.
    final hasRegion = user.homeRegion != null;
    // ① 신분 확인: 신분증 이미지 등록 여부 (idCardImagePath 신규 flow + idCardImageUrl legacy 양쪽 허용)
    final hasId = user.hasIdDocument;
    // ② 급여정보: 계좌 3필드 + 통장사본 등록 여부 (presence only)
    final hasWage = user.hasBankAccount && user.hasBankbookDocument;

    // 하나라도 남으면 모든 줄을 보인다 — 하나만 하면 끝나는 것처럼 말하지 않는다. 전부 끝나면 카드 없음.
    final completed = (hasRegion ? 1 : 0) + (hasId ? 1 : 0) + (hasWage ? 1 : 0);
    if (completed == 3) return const SizedBox.shrink();

    // 국적 미확정(새 계정 · 서류 전)은 두 서류를 같은 틀로 받는다는 것을 말한다. 옛 계정 문구는 '신분증'.
    final idTitle = user.isNationalityUnconfirmed ? '신분증 또는 외국인등록증 등록' : '신분증 등록';
    void openDocuments() => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DocumentManagementScreen()),
        );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)), // [CP03 Q9] 간격은 본문 리듬
      child: StartReadinessCard(
        items: [
          StartReadinessItem(
            icon: Icons.place_outlined,
            title: '일할 지역 고르기',
            // [판정287 C287-02] 거리 계산이 없다 — 행정구역(시·군·구) 우선이라는 실제 동작만 말한다.
            subtitle: '선택한 지역의 일자리를 먼저 보여 드려요',
            done: hasRegion,
            onTap: () => openHomeRegionSetup(context),
          ),
          StartReadinessItem(
            icon: Icons.badge_outlined,
            title: idTitle,
            subtitle: '지원하기 전에 한 번 등록해요',
            done: hasId,
            onTap: openDocuments,
          ),
          StartReadinessItem(
            icon: Icons.account_balance_outlined,
            title: '급여 계좌 · 통장사본 등록',
            subtitle: '급여를 받을 본인 계좌예요',
            done: hasWage,
            onTap: openDocuments,
          ),
        ],
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
  /// [PERF-P6] 홈 추천 섹션에 **보이는** 공고(최대 2)와 STATE — 화면과 사진 미리 불러오기가 같이 쓴다.
  ///   (분류 규칙은 예전 `_buildRecommendSection` 본문 그대로 옮겼다.)
  ({int recState, List<TOModel> tos}) _homeRecommendPick(
      UserModel user, List<TOModel> allRecommended) {
    final homeRegion = user.homeRegion;
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
    return (recState: recState, tos: displayedTos);
  }

  /// [PERF-P6] 추천 카드 사진 칸의 **실제 표시 폭**(dp) — 카드 LayoutBuilder 가 마지막으로 잰 값.
  ///   null = 아직 그린 적 없음(미리 불러오기를 건너뛴다) · 0 = 큰 글자로 사진 칸을 숨김(건너뛴다).
  double? _recommendImageW;

  /// [PERF-P6] 추천 카드 사진 디코드 폭(px) — 표시 폭 × 화면 배율 × cover 여유 2.
  ///   사진은 `BoxFit.cover` 로 그린다. 칸 높이(IntrinsicHeight = 글자 덩이 높이)가 폭보다 크고
  ///   사진은 대개 가로형이라, 실제로 그려지는 사진 폭은 칸 폭의 1.3~2배가 된다. 칸 폭 그대로
  ///   디코드하면 그만큼 늘려 그려 흐려진다. 원본(최대 1920px) 디코드보다는 여전히 훨씬 작다.
  ///   화면 위젯과 미리 불러오기가 **같은 값**을 써야 이미지 캐시 키가 같아 한 번만 받는다.
  static int _recommendImageDecodeW(double displayW, double dpr) =>
      (displayW * dpr * 2).round();

  /// [PERF-P6] 보이는 추천 카드 사진(최대 2장)을 화면 위젯과 같은 키·크기로 미리 불러온다.
  ///   기다리지 않는다(첫 프레임·홈 읽기와 무관) · 실패는 삼킨다(카드가 자리표시를 그린다).
  ///   사진 칸이 숨겨졌거나 아직 잰 적이 없으면 아무것도 하지 않는다.
  /// [impl_12 · P2] 지금 보이는(날짜 미선택) 추천 두 장을 표시 DTO 로 만들어 저장한다. 날짜를 골라 둔 상태면 저장하지 않는다.
  void _saveRecommendCache(UserModel user, {required bool complete}) {
    if (!complete) return;
    final picks = _homeRecommendPick(user, _getRecommendedTos(user)).tos.take(HomeRecommendCache.maxCards);
    final cards = [
      for (final to in picks)
        HomeRecommendCard(
          toId: to.id,
          title: to.title.isNotEmpty ? to.title : to.businessName,
          businessName: to.businessName,
          regionLabel: _recommendLocationText(to),
          dateLabel: _recommendDateTextUnselected(
              to, to.workDetails.where((d) => !d.isClosed && !d.isTimeExpired).toList()),
          wageLabel: _recommendWageText(
              to.workDetails.where((d) => !d.isClosed && !d.isTimeExpired).toList()),
          workTypeIcon: to.workDetails.firstOrNull?.workTypeIcon,
          imageUrl: _businessCache[to.businessId]?.mainImageUrl, // 생성자가 공개 대표사진 출처·경로만 남긴다
        ),
    ];
    unawaited(_recCache.saveSuccess(
        uid: user.uid, scope: _recScope(user), cards: cards, fromCompleteSuccess: true));
  }

  void _precacheRecommendImages(UserModel user, Map<String, BusinessModel> cache) {
    final w = _recommendImageW;
    if (!mounted || w == null || w <= 0) return;
    final memW = _recommendImageDecodeW(w, MediaQuery.devicePixelRatioOf(context));
    final picks = _homeRecommendPick(user, _getRecommendedTos(user)).tos.take(2);
    for (final to in picks) {
      final url = cache[to.businessId]?.mainImageUrl;
      if (url == null || url.isEmpty) continue;
      unawaited(precacheImage(
        ResizeImage.resizeIfNeeded(memW, null, CachedNetworkImageProvider(url)),
        context,
        onError: (Object e, StackTrace? st) =>
            debugPrint('⚠️ 추천 사진 미리 불러오기 실패(무시)'),
      ));
    }
  }

  /// [impl_12 · P2] 캐시 추천 묶음 — 표시 문구·공개 대표사진만. 누르면 아무 일도 없다(live 상세는 확인 뒤 카드가 맡는다).
  Widget _cachedRecommendBlock(BuildContext context, double s, HomeRecommendSnapshot snap) {
    final k = snap.savedAt.toUtc().add(const Duration(hours: 9));
    final hhmm = '${k.hour.toString().padLeft(2, '0')}:${k.minute.toString().padLeft(2, '0')}';
    final note = '마지막 확인 $hhmm · 확인 중';
    return Column(
      key: const ValueKey('worker-home-recommend-cached'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: '추천 일자리 마지막 확인 $hhmm, 지금 다시 확인하고 있어요',
          excludeSemantics: true,
          child: Padding(
            padding: EdgeInsets.only(bottom: 8 * s),
            child: Text(TextLayout.keepWords(note), style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        ),
        for (var i = 0; i < snap.cards.length; i++) ...[
          if (i > 0) SizedBox(height: 8 * s),
          _cachedRecommendCard(context, s, snap.cards[i]),
        ],
      ],
    );
  }

  Widget _cachedRecommendCard(BuildContext context, double s, HomeRecommendCard c) {
    return Container(
      padding: EdgeInsets.all(12 * s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14 * s),
        border: Border.all(color: AppColors.borderLight, width: 1.5),
      ),
      child: LayoutBuilder(builder: (context, box) {
        // 이미지 칸 규칙은 live 카드와 같다(글자 영역 ≥ 160 × 글자 배율 · 96→72→숨김).
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        var imageW = 0.0;
        for (final w in [96 * s, 72 * s]) {
          if (box.maxWidth - w - 10 * s >= 160.0 * textScale) {
            imageW = w;
            break;
          }
        }
        final placeholder = JobImagePlaceholder(workTypeIcon: c.workTypeIcon);
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (imageW > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12 * s),
                child: SizedBox(
                  width: imageW,
                  child: c.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: c.imageUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: _recommendImageDecodeW(imageW, MediaQuery.devicePixelRatioOf(context)),
                          placeholder: (_, __) => placeholder,
                          errorWidget: (_, __, ___) => placeholder,
                        )
                      : placeholder,
                ),
              ),
              SizedBox(width: 10 * s),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(c.title, style: AppTextStyles.jobTitle(), maxLines: 2, overflow: TextOverflow.ellipsis),
                SizedBox(height: 2 * s),
                Text(c.businessName, style: AppTextStyles.businessName(), maxLines: 2, overflow: TextOverflow.ellipsis),
                SizedBox(height: 6 * s),
                if (c.dateLabel.isNotEmpty) _iconRow(icon: Icons.calendar_today_outlined, text: c.dateLabel, s: s),
                if (c.dateLabel.isNotEmpty) SizedBox(height: 3 * s),
                if (c.regionLabel.isNotEmpty) _iconRow(icon: Icons.location_on_outlined, text: c.regionLabel, s: s),
                if (c.wageLabel.isNotEmpty) ...[
                  SizedBox(height: 6 * s),
                  Text(c.wageLabel, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ],
              ]),
            ),
          ]),
        );
      }),
    );
  }

  Widget _buildRecommendSection(BuildContext context, double s, UserProvider up) {
    final user = up.currentUser;
    if (user == null) return const SizedBox.shrink();

    // 전체 정렬 목록 → 홈에는 상위 2개만 표시. [판정286] 후보 총수는 더 이상 보이지 않는다(도착 수량과 같다는 보장 없음).
    final allRecommended = _getRecommendedTos(user);
    final homeRegion = user.homeRegion;

    // ── STATE A/B/C/D 분류 — homeRegion 기반 표시 전략 ──────────────
    // STATE A: 내 city TO 2건 이상 → city TO 2건만 표시, city 부제목
    // STATE B: 내 city TO 1건     → city TO 1건 + 타지역 TO 1건 혼합 표시, 부제목 없음
    // STATE C: 내 city TO 0건     → 타지역 TO 2건 표시 + 지역 안내 배너
    // STATE D: 전체 TO 0건        → 빈 상태 안내 메시지
    // STATE 0 (homeRegion 없음 또는 로딩 중): 기존 동작 유지 (상위 2건)
    // [PERF-P6] 분류는 `_homeRecommendPick` 하나 — 사진 미리 불러오기가 **실제로 보이는 두 장**을 고르는 데 같은 답을 쓴다.
    final pick = _homeRecommendPick(user, allRecommended);
    final List<TOModel> displayedTos = pick.tos;
    final int recState = pick.recState; // 0=no_home, 1=A, 2=B, 3=C, 4=D

    // ── [판정286] 섹션 제목 — 미선택 「추천 일자리」(신규·경험·지역 무관) ↔ 선택 「M월 D일 일자리」 ──
    //   경험별 `추천/둘러볼` 분기·후보 수 부제·머리 `전체 보기`는 대체했다. 탐색 행동은 섹션 맨 아래 하나뿐.
    final selected = _selectedDateChip;
    final String sectionTitle =
        selected != null ? '${selected.month}월 ${selected.day}일 일자리' : '추천 일자리';
    // 지역 우선 안내 — 행정구역(시·군·구) 우선이라는 사실만 말한다(거리 계산 없음 · `근처`/`가까운 순` 0).
    //   날짜를 고르면 제목에 날짜가 있으므로 부제를 두지 않는다(기존 규칙).
    final String? sectionSubtitle =
        (selected == null && recState == 1) ? '${homeRegion!.city} 일자리를 먼저 보여드려요' : null;
    // 탐색 행동 하나 — 미선택은 일반 일자리 탭(새 날짜 만들지 않음), 선택은 같은 KST 하루 날짜 필터.
    //   정상0·로딩·실패에도 유지한다(수량 없음 · 도착 수량·지원 가능을 약속하지 않음). 재시도는 별개 복구 행동.
    final String ctaLabel = selected != null ? '${selected.month}월 ${selected.day}일 일자리 보기' : '일자리 더 보기';
    void onCta() {
      final scope = UserTabScope.of(context);
      if (selected != null) {
        scope?.switchToTabWithDate(1, selected);
      } else {
        scope?.switchToTab(1);
      }
    }

    final infoStrong = TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600);
    final infoSub = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    // [BL287-01] 겹침으로 빠진 공고 수(확인된 사유만) · 한 줄 안내.
    final conflictExcluded = _conflictExcludedOn(user);
    Widget conflictNote(String text) => Padding(
          padding: EdgeInsets.only(top: 8 * s),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: EdgeInsets.only(top: 2 * s),
              child: Icon(Icons.info_outline, size: 14 * s, color: AppColors.textSecondary),
            ),
            SizedBox(width: 6 * s),
            Expanded(
              child: Text(TextLayout.keepWords(text), semanticsLabel: text,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ]),
        );
    Widget emptyNotice(String head, String sub) => Container(
          padding: EdgeInsets.symmetric(vertical: 8 * s),
          alignment: Alignment.center,
          child: Column(children: [
            Text(TextLayout.keepWords(head), semanticsLabel: head, style: infoStrong, textAlign: TextAlign.center),
            SizedBox(height: 4 * s),
            Text(TextLayout.keepWords(sub), semanticsLabel: sub, style: infoSub, textAlign: TextAlign.center),
          ]),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const ValueKey('worker-home-jobs-section'), // 영역 키 — 시험·캡처가 이 섹션만 잰다(동작 없음)
          color: Colors.white,
          // [CP03 Q9] 좌우 화면 여백만 — 섹션 사이 24 는 본문 리듬이 맡는다.
          padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          _sectionHeader(context, title: sectionTitle, subtitle: sectionSubtitle),
          const SizedBox(height: ConceptSpace.sectionTitleToCard),
          // 상태 — 로딩 → 공고 조회 실패 → 정상 표시 0 → 카드(285 우선순위 그대로). 안내는 이 섹션에서 한 번만.
          if (!_mainRoundDone && selected == null && _recSnapshot != null)
            // [impl_12 · P2] 마지막 성공 추천 — live 확인 전까지만 · '확인 중' 표지 · 누름 0
            _cachedRecommendBlock(context, s, _recSnapshot!)
          else if (_isLoadingData)
            Column(children: [
              _recommendSkeletonCard(s),
              SizedBox(height: 8 * s),
              _recommendSkeletonCard(s),
            ])
          // [R8-P7.4] 못 읽은 것을 "공고 없음"으로 말하지 않는다.
          //   두 빈 화면 문구보다 먼저 온다 — 목록이 빈 이유가 실패라면
          //   날짜별 문구든 전체 문구든 모두 사실이 아니다.
          else if (_postingsFailed)
            _postingsFailedCard(s)
          else if (selected != null && displayedTos.isEmpty)
            // 날짜 선택 + 그날 표시할 공고 0 — 다른 날 안내도 여기서 한 번(날짜 변경은 바로 위 띠).
            //   [BL287-01] 확정 근무와 겹쳐 빠진 공고가 확인되면 그 수를 함께 말한다(단정 0 · 사유 불명이면 기존 문구만).
            Column(children: [
              emptyNotice('이 날짜에 표시할 일자리가 없어요', '다른 날짜도 골라 보세요'),
              if (conflictExcluded > 0) conflictNote('확정된 근무 시간과 겹치는 일자리 $conflictExcluded개는 뺐어요'),
            ])
          // [판정285 C285-02] 정상 조회 뒤 표시 목록 0 — 지역 유무와 무관(recState 4 는 지역 분류 결과일 뿐 빈 조건이 아니다).
          else if (displayedTos.isEmpty)
            // STATE D: 전체 TO 없음 — [DU1 구현98 S080 V8·V9] 위아래 8 · 설명 textSecondary.
            emptyNotice('지금 표시할 일자리가 없어요', '새 일자리가 등록되면 여기에서 확인할 수 있어요')
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
                            '${homeRegion.city}에 표시할 일자리가 없어요',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 2 * s),
                          Text(
                            '다른 지역 일자리를 보여드려요',
                            // [DU474] textHint(grey400 · grey50 위 약 1.8) → textTertiary(5.03 · 보조 안내 · DU470 실패 안내와 같다).
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // 카드 목록 (STATE A/B/C/0 공통) — 최대 2(선택일이면 그날 공고만 · 다른 날로 채우지 않는다)
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
            // [BL287-01] 카드가 있어도 겹쳐서 빠진 공고가 확인되면 카드 아래 한 줄.
            if (conflictExcluded > 0) conflictNote('확정된 근무 시간과 겹치는 일자리 $conflictExcluded개는 빼고 보여 드려요'),
          ],
          // [판정286] 섹션 맨 아래 탐색 행동 하나 — 보조 위계(아웃라인 · brand · 최소 48). 큰 채움 CTA 를 쓰지 않는다.
          const SizedBox(height: ConceptSpace.infoGroupGap),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onCta,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brand,
                side: const BorderSide(color: AppColors.brand),
                minimumSize: const Size(ConceptSpace.minTouch, ConceptSpace.minTouch),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                TextLayout.keepWords(ctaLabel),
                semanticsLabel: ctaLabel,
                textAlign: TextAlign.center,
                style: ConceptText.button().copyWith(color: AppColors.brand),
              ),
            ),
          ),
            ],
          ),
        ),  // 내부 Container 닫기
      ],  // 외부 Column.children 닫기
    );  // 외부 Column 닫기
  }

  // ── [impl_12 · P2] 추천 카드 문구 — 카드와 추천 표시 캐시(DTO)가 **같은 함수**를 쓴다(어긋남 0) ──────────
  /// 지역 줄(시·군·구).
  static String _recommendLocationText(TOModel to) {
    final city = to.businessCity;
    final district = to.businessDistrict;
    return [
      if (city != null && city.isNotEmpty) city,
      if (district != null && district.isNotEmpty) district,
    ].join(' ');
  }

  /// 날짜 미선택 모드의 날짜 줄 — 그룹 전체 기간 + 시간대 요약.
  static String _recommendDateTextUnselected(TOModel to, List<WorkDetailData> activeDetails) {
    String dateText;
    // 날짜 미선택 모드: Group 전체 기간 요약
    if (to.isFlexType) {
      final rs = to.rangeStart;
      if (rs != null) {
        // [TZ-FIX] KST calendar date 기준 표시 — device timezone 무관
        dateText = FormatHelper.formatDateShort(rs);
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
        // [TZ-FIX] KST calendar date 기준 표시 — device timezone 무관
        dateText = FormatHelper.formatDateShort(rs);
        if (endDt != null) dateText += ' ~ ${FormatHelper.formatDateShort(endDt)}';
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
    return dateText;
  }

  /// 급여 줄 — [details] 중 급여가 있는 것의 최저(범위면 `~`).
  static String _recommendWageText(List<WorkDetailData> details) {
    // [F293-WAGE-01] 시급 업무가 있으면 이 카드가 대표하는 업무 각각을 환산한 하루 예상 범위 + 시급 범위(보조) + 짧은 말.
    //   시급과 다른 유형이 섞이면 '업무별 급여 확인' · 일부 계산 불가면 '업무별 예상 금액 확인'(0원 합성 없음).
    final er = ExpectedWageRange.ofWorkDetails(details);
    final daily = ExpectedWageText.dailyRange(er);
    if (daily != null) {
      final rate = ExpectedWageText.rateRange(er);
      return [daily, if (rate != null) rate, if (er.complete) ExpectedWageText.shortNote].join(' · ');
    }
    final wageSources =
        details.where((d) => d.wage > 0).toList();
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
    return wageText;
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
    final isNearby =
        homeRegion != null && city != null && city == homeRegion.city;
    final locationText = _recommendLocationText(to); // [impl_12] 카드·캐시 공용

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
        final wd = FormatHelper.toKstDate(a.workDate);
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
          ? '$dayStr · 업무 $count개'
          : '$dayStr · 표시할 업무 없음';
    } else {
      dateText = _recommendDateTextUnselected(to, activeDetails); // [impl_12] 카드·캐시 공용
    }

    // ── 급여 범위 ─────────────────────────────────────────────
    // 날짜 선택 시: 가능한 Work Slot(충돌 제외) 기준
    // 날짜 미선택 시: 전체 활성 Work Slot 기준 (최저~최고 범위)
    final wageText = _recommendWageText(availableDetails); // [impl_12] 카드·캐시 공용

    // [CP03] 상태 배지(`마감임박` = 남은 인원≤2, `모집중` = 그 밖)는 삭제했다 — 실제 마감 기한·공개모집 상태의
    //   근거가 아니었다(문구 감사 U:4023–4038). 후보 필터·정렬·reader 는 그대로다.

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
      reasonLabel = '함께 살펴볼 업무';
      reasonIcon = Icons.event_available_outlined;
    } else if (expCount != null && expCount > 0) {
      reasonLabel = '경험 있는 업무';
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
        // [CARD-TWO-BLOCK] 카드를 **두 덩이**로 나눈다.
        //
        //   위: 이미지 + (제목·사업장명·날짜·지역)  — 이미지 높이는 지역 줄까지
        //   아래: 급여 + 추천사유 + 화살표          — 카드 **전폭**
        //
        //   예전에는 급여 줄까지 정보 컬럼 안에 있어서 이미지가 그 높이까지
        //   늘어났고(세로로 길쭉), 급여 줄은 이미지 폭(96s)과 간격(10s)을
        //   빼고 남은 폭만 썼다. 전폭으로 내리면 가용 폭이
        //     360dp 204.0 → 299.4 · 390dp 234.0 → 329.4 · 411dp 238.0 → 344.0
        //   이 되어 급여와 추천사유가 다시 한 줄에 들어간다
        //   (320dp 는 262.6 — 가장 긴 조합만 다음 줄).
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // [COMMON-TEXT-LAYOUT.28] 이미지 칸(96)이 고정이라 큰 글자에서 제목이 '[합성] …', 시간이 '09:00~1…' 로
            //   잘렸다. 카드 폭이 모자라면(글자 배율 반영) 장식 이미지 칸을 내리고 글자에 폭을 준다.
            // [대표 지적 2026-11-26 · 판정286 묶음] 옛 문턱 `카드 안쪽 ≥ 300 × 글자 배율`은 360dp 폰의 안쪽(≈295)에서도
            //   늘 이미지를 숨겼다. 문턱을 **이미지 뒤 남는 글자 영역**으로 바꾼다: 글자 영역 ≥ 160 × 글자 배율
            //   (제목 17/700 약 9자 + 찜 아이콘이 한 줄에 드는 폭). 96*s 가 안 되면 72*s 로 한 번 줄이고, 그래도 안 되면 숨긴다.
            //   360/1.0 · 320/1.0 = 96 표시 · 320/1.3 이상 큰 글자 = 숨김(글자 우선). 이미지 없는 사업장은 JobImagePlaceholder 그대로.
            LayoutBuilder(builder: (context, c) {
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            const kTextMinBase = 160.0;
            var imageW = 0.0;
            for (final w in [96 * s, 72 * s]) {
              if (c.maxWidth - w - 10 * s >= kTextMinBase * textScale) {
                imageW = w;
                break;
              }
            }
            final showImage = imageW > 0;
            // [PERF-P6] 미리 불러오기가 같은 크기·같은 숨김 판정을 쓰도록 마지막으로 잰 칸 폭을 남긴다(상태 아님 · 다시 그리지 않음).
            _recommendImageW = imageW;
            final imageDecodeW = _recommendImageDecodeW(
                imageW, MediaQuery.devicePixelRatioOf(context));
            return IntrinsicHeight(
              child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 사업장 이미지 (너비 고정·높이=지역 줄까지) ─────────
            if (showImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12 * s),
              child: SizedBox(
                width: imageW,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        // [PERF-P6] 원본 해상도(최대 1920px) 대신 표시 크기로 디코드 — 미리 불러오기와 같은 값.
                        memCacheWidth: imageDecodeW,
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
            ],
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
                        // 공고 제목은 식별 정보 — 두 줄까지(아주 길 때만 말줄임).
                        child: Text(
                          to.title.isNotEmpty ? to.title : to.businessName,
                          style: AppTextStyles.jobTitle(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // [CP03] `모집중`/`마감임박` 배지와 그 간격 삭제(UH167·168) — 실제 기한·공개모집 근거가 없다.
                      SizedBox(width: 6 * s),
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
                          // [DU470] 비활성 하트 grey400(1.88) → textSecondary(공고 카드 DU458 · 일자리 탭 DU310 과 같다).
                          color: isFav ? AppColors.error : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 2 * s),
                  // 사업장명 (서브타이틀)
                  Text(
                    to.businessName,
                    style: AppTextStyles.businessName(),
                    maxLines: 2,
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
                  // 지역 행 — 위 덩이의 마지막. 이미지 높이가 여기까지다.
                  if (locationText.isNotEmpty)
                    _iconRow(
                        icon: Icons.location_on_outlined,
                        text: locationText,
                        s: s),
                ],
              ),
            ),
          ],
              ),
            );
            }),
            SizedBox(height: 8 * s),
            // 구분선
            Divider(
                height: 1,
                thickness: 0.5,
                color: AppColors.borderLight),
            SizedBox(height: 8 * s),
            // 급여 범위 + 추천사유(1개) + 화살표 — 카드 전폭
            //
            // [RECRUITABLE-CARD-OVERFLOW] 이 행의 세 조각에 **flex 가 하나도
            //   없었다.** `Spacer` 는 남는 공간을 먹는 역할이라, 공간이
            //   모자라면 0 으로 줄고 그 뒤로는 그대로 넘쳤다. 그때는 이 행이
            //   정보 컬럼 안에 있어 이미지 폭(96s)과 간격(10s)까지 빼고 남은
            //   폭만 썼다 — 실측(번들 NotoSansKR):
            //
            //     옛 가용  320dp 172.5 · 360dp 204.0 · 390dp 234.0 · 411dp 238.0
            //     360dp  시급 12,000원 + 내 업무 경험과 일치 = 237.5 → 33.5px 넘침
            //     390dp  일급 150,000원~ + 내 업무 경험과 일치 = 257.7 → 23.7px
            //            (기기에서 본 `RIGHT OVERFLOWED BY 24 PIXELS`)
            //
            //   [CARD-TWO-BLOCK] 이 행을 카드 전폭으로 내린 뒤 가용 폭은
            //     320dp 262.6 · 360dp 299.4 · 390dp 329.4 · 411dp 344.0
            //   이다. 360dp 이상에서는 모든 급여·사유 조합이 **한 줄**이고,
            //   320dp 만 가장 긴 조합(월급 3,000,000원~ + 내 업무 경험과 일치
            //   = 257.8 vs 243.9)에서 다음 줄로 내려간다.
            //
            //   금액은 끝자리가 잘리면 **다른 금액으로 읽힌다** — 줄이지
            //   않는다. 추천 사유도 줄이면 뜻이 사라진다. 그래서 둘을
            //   `Wrap` 에 넣어 자리가 모자라면 **다음 줄로 내려가게** 한다.
            //   화살표는 바깥에 고정해 오른쪽 끝을 지킨다.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                      Expanded(
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6 * s,
                          runSpacing: 4 * s,
                          children: [
                            if (wageText.isNotEmpty)
                              Text(
                                wageText,
                                style: AppTextStyles.pay(),
                              ),
                            // 추천 사유 1개 (없으면 미표시)
                            if (reasonLabel != null)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(reasonIcon,
                                    size: 12 * s, color: AppColors.infoDark),
                                SizedBox(width: 3 * s),
                                // 큰 배율에서는 이 칩 하나가 줄 폭을 넘을 수
                                //   있다. 그때는 문구가 **다음 줄로 흐른다** —
                                //   줄이거나 자르지 않는다.
                                Flexible(
                                  child: Text(
                                    reasonLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.infoDark,
                                    ),
                                  ),
                                ),
                              ]),
                          ],
                        ),
                      ),
                      SizedBox(width: 4 * s),
                      Icon(Icons.chevron_right_rounded,
                          size: 18 * s, color: AppColors.grey400),
                    ],
                  ),
          ], // 바깥 Column.children
        ),
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
    // [R7-P2-1 P21-H] 라벨·금액 어느 쪽에도 flex 가 없어서 320dp·배율 1.3 에
    //   `1,250,000원` 이 17px, 배율 2.0 에 36px 넘쳤다. **금액은 끝자리가
    //   잘리면 다른 금액으로 읽힌다** — 줄이지 않는다. 대신 자리가 모자라면
    //   금액이 다음 줄로 내려가게 한다(`Wrap`). 들어갈 때의 모양은
    //   이전과 같다(라벨 왼쪽 · 금액 오른쪽).
    //   (부모 Column 이 가운데 정렬이라 폭을 명시해야 좌·우가 갈린다)
    return SizedBox(
      width: double.infinity,
      child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 4 * s,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 13,
              color: labelColor,
              fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
            )),
        value == null
            ? SizedBox(
                width: 80 * s,
                height: 16 * s,
                child: LinearProgressIndicator(
                  borderRadius: BorderRadius.circular(4),
                  color: AppColors.border,
                  backgroundColor: AppColors.borderLight,
                ))
            : Text(value,
                style: TextStyle(
                  fontSize: valueBold ? 15 : 13,
                  fontWeight: valueBold ? FontWeight.w900 : FontWeight.w600,
                  color: valueColor,
                  letterSpacing: -0.3,
                )),
        ],
      ),
    );
  }

  /// 아이콘 + 텍스트 한 줄 행 (날짜/지역 공통)
  Widget _iconRow(
      {required IconData icon, required String text, required double s}) {
    return Row(
      children: [
        Icon(icon, size: 13 * s, color: AppColors.textTertiary),
        SizedBox(width: 4 * s),
        // [COMMON-TEXT-LAYOUT.28] 날짜·시간·지역은 말줄임하지 않는다('09:00~1…') — 모자라면 줄을 바꾼다.
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.jobMeta(),
          ),
        ),
      ],
    );
  }

  /// 스켈레톤 카드 — 시안 카드 구조와 동일한 placeholder
  /// [R8-P7.4] 공고를 못 읽었을 때의 자리.
  ///
  /// "없어요"가 아니라 "못 불러왔어요"라고 말하고, 다시 시도할 길을 준다.
  /// 빈 상태와 같은 여백·정렬을 쓴다 — 새 표현을 만들지 않는다.
  Widget _postingsFailedCard(double s) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 20 * s),
      alignment: Alignment.center,
      child: Column(
        children: [
          Text(
            '공고를 불러오지 못했어요',
            style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 4 * s),
          Text(
            // [DU472] 지원 현황 실패 안내와 같은 방식(낱말 사이 줄바꿈 · 읽기는 원문).
            TextLayout.keepWords('잠시 후 다시 시도해 주세요'),
            semanticsLabel: '잠시 후 다시 시도해 주세요',
            // [DU470] textHint(grey400) → textTertiary(지원 현황 실패 안내와 같다).
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
          ),
          SizedBox(height: 10 * s),
          TextButton(
            onPressed: _isLoadingData ? null : () => _loadHomeData(),
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }

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
  List<TOModel> _getRecommendedTos(UserModel user, {HomeRecruitableProjection? projection}) {
    // [R7-P4.4E.8A] 여기 있던 `appliedToIds.contains(to.id)` 를 지웠다.
    //   지원서 하나가 공고 전체를 지웠고, 그래서 flex 의 다른 날짜 모집이
    //   사라졌다. 판정은 날짜칩과 **같은** projection 이 한다.
    // [BL287-01] [projection] 을 주면 그것으로 같은 필터를 돌린다(겹침 제외 수 비교용 · 기본은 실제 후보).
    final proj = projection ?? _recruitable;

    // ── 날짜 선택 시: 해당 날짜의 확정 일정 캐시 (충돌 검사용) ──
    final List<ApplicationModel> confirmedOnDate;
    if (_selectedDateChip != null) {
      confirmedOnDate = _applications.where((a) {
        if (!AppStatus.confirmedStatuses.contains(a.status)) return false;
        final wd = FormatHelper.toKstDate(a.workDate);
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
          to.status == TOStatus.scheduled) { return false; }
      if (to.isDeleted) return false;
      // [R8-P9D] 위 집계와 같은 기준 — flex 는 공고 전체 정원으로 닫지 않는다.
      if (!to.isFlexType &&
          (to.status == TOStatus.full ||
              (to.totalRequired > 0 &&
                  to.totalConfirmed >= to.totalRequired))) {
        return false;
      }
      // 지원 여부로 공고를 버리지 않는다 — 어느 하루라도 신규 지원 가능한
      //   근무가 남아 있으면 후보다. projection 이 아직 없으면(첫 프레임)
      //   남긴다 — 모르는 것을 "없다" 로 바꾸지 않는다.
      if (proj != null && !proj.hasAnyDate(to.id)) return false;
      return true;
    }).toList();

    // ── 날짜 선택 시: 해당 날짜에 슬롯이 있는 TO만 ───────────────
    if (_selectedDateChip != null) {
      final sd = _selectedDateChip!;
      const dowLabels = ['월', '화', '수', '목', '금', '토', '일'];
      final dowLabel = dowLabels[sd.weekday - 1];

      final sdKey = FormatHelper.toKstDateKey(sd);

      candidates = candidates.where((to) {
        // [R7-P4.4E.8A] flex 는 **그 날짜에 신규 지원 가능한 근무가 남아
        //   있는지**로 본다. 날짜칩과 같은 projection 을 쓴다 — 칩은 1인데
        //   목록은 0 같은 어긋남을 만들지 않는다.
        //   날짜를 확실히 알 때만 걸러내고, 모르면 남긴다 — 서버가 판정한다.
        if (to.isFlexType) {
          if (proj != null) return proj.isRecruitable(to.id, sd);
          if (to.slotDateKeys.isEmpty || !to.slotDatesLookComplete) return true;
          return to.slotDateKeys.contains(sdKey);
        }

        // 신규 preset: workStartAvailableFrom ~ Until / custom·legacy: rangeStart ~ rangeEnd
        final rs = to.hasWorkStartAvailableRange
            ? to.workStartAvailableFrom
            : to.rangeStart;
        final re = to.hasWorkStartAvailableRange
            ? to.workStartAvailableUntil
            : to.rangeEnd;
        if (rs == null) return false;
        // 날짜 범위 검사
        final sdDate = DateTime.utc(sd.year, sd.month, sd.day);
        final rsDate = FormatHelper.toKstDate(rs);
        if (sdDate.isBefore(rsDate)) return false;
        if (re != null) {
          final reDate = FormatHelper.toKstDate(re);
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
      //    [INVITE-CAPACITY] 슬롯 공고는 합계로 남은 자리를 셀 수 없다 — 순위를 주지 않는다.
      final remA = (!a.isFlexType && a.totalRequired > 0)
          ? a.totalRequired - a.totalConfirmed : 999;
      final remB = (!b.isFlexType && b.totalRequired > 0)
          ? b.totalRequired - b.totalConfirmed : 999;
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
      // [CP03 Q9] 좌우 화면 여백만 — 섹션 사이 24 는 본문 리듬이 맡는다.
      padding: EdgeInsets.symmetric(horizontal: _gutter(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더 — `내 근무 기록`(실제 누적 근무·시간·출근율·업무 경험의 요약, UH182)
          _sectionHeader(context, title: '내 근무 기록'),
          const SizedBox(height: ConceptSpace.sectionTitleToCard),
          // ── 신규 사용자 Empty State (근무 이력 없음) ──
          if (!_isLoadingData && totalDays == 0) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('아직 완료한 근무가 없어요',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    )),
                SizedBox(height: 4 * s),
                // [DU306] 같은 홈 지원 현황 빈 안내(DU1 구현98)와 같은 처리 — 설명 textHint(1.88:1) → textSecondary,
                //   탐색 링크 infoDark → brand, 링크 receiver 높이 48(글자 밖 빈 곳도 탭). 늘어난 receiver 위 여유가
                //   보이는 간격을 대신하도록 위 간격 16*s → 4*s. 문구·목적지(일자리 탭)는 그대로다.
                Text('근무를 마치면 기록이 쌓여요',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                SizedBox(height: 4 * s),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => UserTabScope.of(context)?.switchToTab(1),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: ConceptSpace.minTouch),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('일자리 찾기',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brand,
                          )),
                      SizedBox(width: 3 * s),
                      Icon(Icons.arrow_forward_rounded,
                          size: 15 * s, color: AppColors.brand),
                    ]),
                  ),
                ),
              ],
            ),
          ] else ...[
          // ── 근무 이력 있는 사용자 — 한 줄 요약 ──
          // [DU194 C5] RichText 는 테마 글꼴(DefaultTextStyle)을 물려받지 않았다 → Text.rich(같은 글자·스타일, 배율은 MediaQuery 그대로)
          Text.rich(
            textScaler: MediaQuery.textScalerOf(context),
            TextSpan(
              style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
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
          // [DU1 구현99 C99-1] 라벨·빈 안내 textHint(흰 바탕 1.879:1 실측) → textSecondary. 라벨(굵게)·안내(보통) 위계는 그대로.
          Text('업무 경험',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              )),
          SizedBox(height: 8 * s),
          // 경험 칩 — 업무 유형별 완료 횟수
          if (sortedStats.isEmpty)
            Text('업무 유형 기록이 없어요',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
          else
            Wrap(
              spacing: 6 * s,
              runSpacing: 5 * s,
              children: sortedStats.take(5).map((e) => Container(
                padding: EdgeInsets.symmetric(horizontal: 13 * s, vertical: 6 * s),
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${e.key} ${e.value}회',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
              )).toList(),
            ),
          SizedBox(height: 4 * s),
          // "근무 기록 보기 →" 링크 — 일정 탭 현재 달로 이동
          // [DU191 C2-a] 위 간격 14→4, 터치 영역 최소 높이 48(고정 높이 아님)·글자 밖 빈 곳도 탭(opaque). 글자·아이콘·색·동작 그대로.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => UserTabScope.of(context)?.switchToScheduleNow(),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // [DU306 §12.2] 탐색 링크 = brand(같은 홈의 `날짜 더보기`·`전체보기`·`일자리 찾기`와 한 색, infoDark 대신).
                Text('근무 기록 보기',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand,
                    )),
                SizedBox(width: 4 * s),
                Icon(Icons.arrow_forward_rounded, size: 16 * s, color: AppColors.brand),
              ]),
            ),
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
        builder: (ctx) => BusinessSelectorSheet(
          businessIds: bizIds,
          businessNames: up.subAdminBusinessNames,
          selectedBusinessId: up.effectiveBusinessId,
        ),
      );
    }
    if (selected == null || !context.mounted) return;
    // [PD-01] switchToAdminMode → notifyListeners() → AuthWrapper 반응형 라우팅 → BusinessAdminShell
    await up.switchToAdminMode(selected);
  }

}

// ─────────────────────────────────────────────────────────────
// [CP03 Q9] 홈 본문 세로 리듬 — 보이는(높이>0) 블록 사이에만 간격을 둔다.
//   같은 수준 카드끼리 12, 그 밖(섹션 앞·뒤, 머리·날짜띠 뒤) 24(정밀 §8 V8).
//   카드들은 숨을 때 SizedBox.shrink(높이 0)를 돌려준다 — 그 자리에는 간격도 남지 않는다.
//   폭은 부모 폭 그대로(세로 Column 의 stretch 와 같다). 그리기·누르기는 자식 위치 그대로다.
// ─────────────────────────────────────────────────────────────
/// [판정290 D290-02] 보정 예약 — 바뀌기 전 기하와 그때의 입력·회차·계정.
class _ZoneAnchor {
  _ZoneAnchor({
    required this.position,
    required this.pixels,
    required this.viewport,
    required this.endY,
    required this.epoch,
    required this.seq,
    required this.uid,
  });
  final ScrollPosition position;
  final double pixels;
  final double viewport;
  /// 바뀌기 전 기준 블록(통합 날짜 영역)의 내용 좌표.
  final double endY;
  final int epoch;
  final int seq;
  final String? uid;
}

enum _Rhythm { block, card, section }

class _RhythmColumn extends MultiChildRenderObjectWidget {
  const _RhythmColumn({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRhythmColumn();
}

class _RhythmSlot extends ParentDataWidget<_RhythmParentData> {
  const _RhythmSlot({required this.kind, required super.child});

  final _Rhythm kind;

  @override
  void applyParentData(RenderObject renderObject) {
    final pd = renderObject.parentData! as _RhythmParentData;
    if (pd.kind != kind) {
      pd.kind = kind;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _RhythmColumn;
}

class _RhythmParentData extends ContainerBoxParentData<RenderBox> {
  _Rhythm kind = _Rhythm.block;
}

class _RenderRhythmColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _RhythmParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _RhythmParentData> {
  /// 같은 수준 카드끼리 12, 그 밖 24.
  static double _gap(_Rhythm prev, _Rhythm next) =>
      (prev == _Rhythm.card && next == _Rhythm.card) ? ConceptSpace.cardGap : ConceptSpace.sectionGap;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _RhythmParentData) child.parentData = _RhythmParentData();
  }

  /// 자식 높이(측정 함수)로 전체 높이를 셈한다 — 높이 0 인 자식은 간격도 더하지 않는다.
  double _stack(double Function(RenderBox child) heightOf) {
    var y = 0.0;
    _Rhythm? prev;
    var child = firstChild;
    while (child != null) {
      final pd = child.parentData! as _RhythmParentData;
      final h = heightOf(child);
      if (h > 0) {
        if (prev != null) y += _gap(prev, pd.kind);
        y += h;
        prev = pd.kind;
      }
      child = pd.nextSibling;
    }
    return y;
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth;
    final childConstraints = BoxConstraints.tightFor(width: w);
    var y = 0.0;
    _Rhythm? prev;
    var child = firstChild;
    while (child != null) {
      final pd = child.parentData! as _RhythmParentData;
      child.layout(childConstraints, parentUsesSize: true);
      final h = child.size.height;
      if (h > 0) {
        if (prev != null) y += _gap(prev, pd.kind);
        pd.offset = Offset(0, y);
        y += h;
        prev = pd.kind;
      } else {
        pd.offset = Offset(0, y);
      }
      child = pd.nextSibling;
    }
    size = constraints.constrain(Size(w, y));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final w = constraints.maxWidth;
    final childConstraints = BoxConstraints.tightFor(width: w);
    return constraints.constrain(Size(w, _stack((c) => c.getDryLayout(childConstraints).height)));
  }

  @override
  double computeMinIntrinsicHeight(double width) => _stack((c) => c.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) => _stack((c) => c.getMaxIntrinsicHeight(width));

  @override
  double computeMinIntrinsicWidth(double height) {
    var w = 0.0;
    var child = firstChild;
    while (child != null) {
      final cw = child.getMinIntrinsicWidth(double.infinity);
      if (cw > w) w = cw;
      child = (child.parentData! as _RhythmParentData).nextSibling;
    }
    return w;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    var w = 0.0;
    var child = firstChild;
    while (child != null) {
      final cw = child.getMaxIntrinsicWidth(double.infinity);
      if (cw > w) w = cw;
      child = (child.parentData! as _RhythmParentData).nextSibling;
    }
    return w;
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
