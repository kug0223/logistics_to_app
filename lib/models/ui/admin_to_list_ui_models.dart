import '../core/to_model.dart';
import '../core/slot_model.dart';
import '../core/work_detail_data.dart';
import '../../utils/close_state_utils.dart';
import '../../utils/format_helper.dart';

/// 공고 리스트 아이템 (관리자용)
///
/// 단일 TOModel을 래핑. flex 타입은 slots를 lazy-load.
/// [Phase 3 리팩토링] groups 구조 제거, slots 구조로 전환.
class TOGroupItem {
  /// 공고 모델 (항상 non-null)
  final TOModel singleTO;

  // flex 타입 슬롯 목록 (lazy-load)
  List<TOItem>? _groupTOs;
  bool isGroupDetailLoaded;

  // 단건 TO 업무 상세 통계 (lazy-load)
  Map<String, Map<String, int>>? workDetailStats;
  bool isWorkDetailLoaded = false;

  /// [POSTING-V2-01B] 통계 조회가 실패했는지 여부.
  /// true면 [workDetailStats]는 실제 수치가 아니므로 화면에 숫자로 표시하면 안 된다.
  bool workDetailStatsFailed = false;

  // flex TO 슬롯 날짜 캐시 (캘린더 필터용)
  List<DateTime>? _slotDates;

  // 캐시된 통계 (UI 갱신용)
  int? _cachedTotalConfirmed;
  int? _cachedTotalPending;
  int? _cachedTotalRequired;

  TOGroupItem({
    required this.singleTO,
    List<TOItem>? groupTOs,
    this.isGroupDetailLoaded = false,
  }) : _groupTOs = groupTOs;

  void setWorkDetailStats(
    Map<String, Map<String, int>> stats, {
    bool statsFailed = false,
  }) {
    workDetailStats = stats;
    isWorkDetailLoaded = true;
    workDetailStatsFailed = statsFailed;
  }

  /// [POSTING-V2-01B] 통계 조회 실패를 기록한다 — 0으로 확정하지 않기 위해.
  void markWorkDetailStatsFailed() {
    isWorkDetailLoaded = true;
    workDetailStatsFailed = true;
  }

  /// [POSTING-V2-01B] 재시도를 위해 통계 로드 상태를 되돌린다.
  void resetWorkDetailStats() {
    isWorkDetailLoaded = false;
    workDetailStatsFailed = false;
  }

  // ── 기본 정보 ──────────────────────────────────────────

  bool get isGrouped => false;
  String get id => singleTO.id;
  String get title => singleTO.title;
  String get businessName => singleTO.businessName;
  String get businessId => singleTO.businessId;
  String get status => singleTO.status;
  /// Firestore 상태 + 날짜 경과를 함께 고려한 실질적 마감 여부.
  /// 마지막 슬롯(또는 계약 종료일)이 오늘 이하면 마감 탭으로 분류.
  ///
  /// 슬롯 로드 여부에 따라 판단 경로가 다름:
  ///   - flex + 슬롯 로드됨 → CloseStateUtils.isToItemClosed (isManualClosed 포함)
  ///   - flex + 슬롯 미로드 → singleTO.isClosed (isManualClosed 포함) + 마지막 날짜 폴백
  ///   - contract → singleTO.isClosed (게시만료 포함) + rangeEnd 폴백
  bool get isClosed {
    final now = DateTime.now();
    final todayDay = FormatHelper.toKstDate(now);

    if (singleTO.isFlexType) {
      // 슬롯 로드된 경우: CloseStateUtils로 통일 판단
      if (_groupTOs != null && _groupTOs!.isNotEmpty) {
        return _groupTOs!.every(
          (t) => CloseStateUtils.isToItemClosed(t, singleTO, now),
        );
      }

      // 슬롯 미로드: Firestore status + 날짜 폴백
      if (singleTO.isClosed) return true;
      DateTime? lastDate;
      if (_slotDates != null && _slotDates!.isNotEmpty) {
        lastDate = _slotDates!.reduce((a, b) => a.isAfter(b) ? a : b);
      }
      if (lastDate == null) return false;
      return FormatHelper.toKstDate(lastDate).isBefore(todayDay);
    }

    // contract TO: TOModel.isClosed(게시만료 포함) + 계약 근무 종료일 체크
    if (singleTO.isClosed) return true;
    final lastDate = singleTO.rangeEnd;
    if (lastDate == null) return false;
    return FormatHelper.toKstDate(lastDate).isBefore(todayDay);
  }
  bool get isManualClosed => singleTO.isManualClosed;
  bool get isPendingPublish => singleTO.isPendingPublish;
  DateTime? get publishAt => singleTO.publishAt;

  /// contract 타입 여부 (구 isLongTerm)
  bool get isLongTerm => singleTO.isContractType;

  // ── 통계 ─────────────────────────────────────────────

  int get totalRequired =>
      _cachedTotalRequired ?? singleTO.totalRequired;
  int get totalConfirmed =>
      _cachedTotalConfirmed ?? singleTO.totalConfirmed;
  int get totalPending =>
      _cachedTotalPending ?? singleTO.totalPending;
  bool get isFull => singleTO.isFull;

  /// Firestore closedReason 코드 — badge contextual 레이블용
  /// 예: "TIME_EXPIRED", "POSTING_EXPIRED", null(수동종료/해당없음)
  String? get closedReasonCode => singleTO.closedReasonCode;

  /// [4I.1] 수동 종료(isManualClosed=true)된 미래 슬롯이 1개 이상 존재하는지 여부.
  /// SlotBatchSelectDialog.closedAndReopenable 기준과 동일한 정책:
  ///   - slot.isManualClosed == true
  ///   - slot.date >= today (KST)
  /// 슬롯 미로드(_groupTOs == null) 시 false 반환 → 메뉴 숨김.
  bool get hasReopenableManualSlots {
    if (_groupTOs == null) return false;
    final today = FormatHelper.toKstDate(DateTime.now());
    return _groupTOs!.any((toItem) {
      final slot = toItem.slot;
      if (slot == null || !slot.isManualClosed) return false;
      return !FormatHelper.toKstDate(slot.date).isBefore(today);
    });
  }

  // ── 날짜 ─────────────────────────────────────────────

  // [POSTING-V2-03R.1] 목록 정렬과 카드 표시가 같은 날짜를 말하게 하는 통로.
  //
  // 값은 WorkforceController가 slot preload 직후 priorityDateOf로 한 번 계산해
  // 넣는다. 카드가 스스로 다시 계산하지 않는다 — 이전에는 카드가
  // `groupTOs.first`(= 마감 여부를 보지 않는 가장 이른 슬롯)를 썼기 때문에,
  // 정렬은 9/25인데 카드에는 9/10이 찍히는 모순이 있었다.
  //
  // null과 "아직 계산 안 됨"은 다르다 — 전자는 "날짜를 알 수 없다"는 확정이다.
  DateTime? _operationalDate;
  bool _operationalDateResolved = false;

  /// 이 공고가 다음에 운영되는 날. 모르면 null.
  DateTime? get operationalDate => _operationalDate;

  /// canonical 계산이 끝났는가. false면 소비자는 날짜를 주장하면 안 된다.
  bool get hasOperationalDate => _operationalDateResolved;

  void setOperationalDate(DateTime? date) {
    _operationalDate = date;
    _operationalDateResolved = true;
  }

  /// [operationalDate]에 해당하는 슬롯. FLEX는 날짜당 슬롯이 하나다.
  ///
  /// fallback(rangeEnd 등)으로 날짜가 정해졌거나 슬롯이 없으면 null —
  /// 그 경우 이 날짜에 대응하는 실제 운영 단위가 없다는 뜻이다.
  TOItem? get operationalSlot {
    final target = _operationalDate;
    if (target == null) return null;
    for (final item in groupTOs) {
      final date = item.slot?.date;
      if (date == null) continue;
      if (FormatHelper.toKstDate(date) == target) return item;
    }
    return null;
  }

  /// 아직 열려 있는 슬롯 수. 종료된 날짜는 세지 않는다.
  int openSlotCount(DateTime now) {
    if (!singleTO.isFlexType) return 0;
    var count = 0;
    for (final item in groupTOs) {
      if (item.slot == null) continue;
      if (CloseStateUtils.isToItemClosed(item, singleTO, now)) continue;
      count++;
    }
    return count;
  }

  /// 시작일. flex: 첫 슬롯 날짜 또는 createdAt; contract: rangeStart
  DateTime get startDate =>
      singleTO.rangeStart ?? singleTO.createdAt;

  /// 종료일. flex: 마지막 슬롯 날짜 또는 createdAt; contract: rangeEnd
  DateTime get endDate =>
      singleTO.rangeEnd ?? singleTO.createdAt;

  /// [R7-P1-2 DEVICE.1E §9] 이 공고의 **운영 마지막 날**. 모르면 null.
  ///
  ///   [isClosed] 가 이미 쓰는 source 선택을 그대로 따른다 — FLEX 는 실제
  ///   슬롯 날짜가 canonical 이고, master 의 `rangeEnd` 는 아니다(R8 에서
  ///   FLEX rangeEnd 를 운영 truth 로 쓰지 않기로 했다). 두 판정이 서로
  ///   다른 날짜를 보면 같은 카드가 `마감됨` 과 `운영 중` 을 동시에 말한다.
  ///
  ///   [endDate] 와 달리 `createdAt` 으로 폴백하지 않는다. 생성일은 운영
  ///   종료일이 아니다 — 그걸로 폴백하면 거의 모든 공고가 과거가 된다.
  ///   모르면 null 을 돌려주고, 판정부는 끝났다고 단정하지 않는다.
  DateTime? get operationEndDate {
    if (!singleTO.isFlexType) return singleTO.rangeEnd;

    DateTime? last;
    for (final item in groupTOs) {
      final date = item.slot?.date;
      if (date == null) continue;
      if (last == null || date.isAfter(last)) last = date;
    }
    if (last != null) return last;

    if (hasSlotDates && slotDates.isNotEmpty) {
      return slotDates.reduce((a, b) => a.isAfter(b) ? a : b);
    }
    // 슬롯을 아직 못 읽었다 — 모르는 것이지 끝난 것이 아니다.
    return null;
  }

  /// 날짜 범위 문자열
  String get dateRangeString {
    if (singleTO.isFlexType) {
      final count = singleTO.totalSlots;
      return count > 0 ? '$count일' : '';
    }
    return singleTO.contractPeriodDisplay;
  }

  // ── 급여 ─────────────────────────────────────────────

  int? get minWage => singleTO.minWage;
  int? get maxWage => singleTO.maxWage;
  String? get wageType => singleTO.wageType;

  // ── 기타 ─────────────────────────────────────────────

  /// 표시명 — groupTitle 설정 시 그것을, 없으면 title 사용
  String get groupName => singleTO.displayGroupTitle;
  DateTime get createdAt => singleTO.createdAt;
  String? get description => singleTO.description;
  String get creatorUID => singleTO.creatorUID;

  /// flex: 슬롯 수; contract: 1
  int get actualDaysCount =>
      singleTO.isFlexType ? singleTO.totalSlots : 1;

  int get workDetailCount => singleTO.workDetailCount;

  // ── TOItem 목록 (flex 전용 날짜별 아이템) ─────────────

  List<TOItem> get groupTOs => _groupTOs ?? [];

  void setGroupTOs(List<TOItem> items) {
    _groupTOs = items;
    isGroupDetailLoaded = true;
  }

  bool get needsGroupDetailLoad => false;

  // flex TO 슬롯 날짜 (캘린더 필터용)
  List<DateTime> get slotDates => _slotDates ?? [];
  bool get hasSlotDates => _slotDates != null;
  void setSlotDates(List<DateTime> dates) => _slotDates = dates;

  /// 공고 모델 직접 접근
  TOModel get masterTO => singleTO;

  // ── 통계 업데이트 ─────────────────────────────────────

  void updateGroupStats({
    required int confirmed,
    required int pending,
    int? required,
  }) {
    _cachedTotalConfirmed = confirmed;
    _cachedTotalPending = pending;
    if (required != null) _cachedTotalRequired = required;
  }
}

/// 슬롯 단위 아이템 (flex 타입 날짜별 행)
class TOItem {
  final TOModel to;
  final SlotModel? slot;

  // 업무 상세 (TO 문서 내 workDetails 배열)
  List<WorkDetailData>? _workDetails;
  bool isWorkDetailLoaded;

  int confirmedCount;
  int pendingCount;
  int totalRequired;

  Map<String, Map<String, int>>? workDetailStats;

  /// [POSTING-V2-01B] 통계 조회가 실패했는지 여부.
  /// true면 [workDetailStats]는 실제 수치가 아니다.
  ///
  /// [R7-P1-2 DEVICE.1E] 생성자로도 받는다.
  ///
  ///   이 flag 는 `setWorkDetails`/`markWorkDetailStatsFailed` 로만 세울 수
  ///   있었다. 그래서 공고 카드가 단건/장기용으로 **합성한** TOItem 은 이
  ///   사실을 전달할 방법 자체가 없었고, 항상 `false` 로 태어났다.
  ///
  ///   카드 자신은 행에 `_singleTOStatsFailed() || stats == null` 로 따로
  ///   OR 해서 넘겼지만, 그 합성 item 을 받은 **다이얼로그는 item 의 flag 를
  ///   직접 읽는다**. `loadTOWorkDetails` 는 실패해도 전부 0 으로 seed 된
  ///   map 을 함께 돌려주므로(`statsFailed: true`), 다이얼로그는 그 0 을
  ///   canonical 정원으로 읽고 `확정 0 · 부족 N` 과 초대 CTA 까지 세울 수
  ///   있었다 — 아무도 읽지 못한 수치를 읽은 것처럼 말하는 것이다.
  bool workDetailStatsFailed;

  TOItem({
    required this.to,
    this.slot,
    List<WorkDetailData>? workDetails,
    required this.confirmedCount,
    required this.pendingCount,
    required this.totalRequired,
    this.workDetailStats,
    this.isWorkDetailLoaded = false,
    this.workDetailStatsFailed = false,
  }) : _workDetails = workDetails;

  List<WorkDetailData> get workDetails => _workDetails ?? [];

  void setWorkDetails(
    List<WorkDetailData> details,
    Map<String, Map<String, int>> stats, {
    bool statsFailed = false,
  }) {
    _workDetails = details;
    workDetailStats = stats;
    isWorkDetailLoaded = true;
    workDetailStatsFailed = statsFailed;
    // confirmedCount/pendingCount는 슬롯 문서의 값을 유지 (헤더 수치 일관성)
  }

  /// [POSTING-V2-01B] 통계 조회 실패를 기록한다.
  /// workDetails가 이미 있으면 그대로 두고 통계만 신뢰 불가로 표시한다.
  void markWorkDetailStatsFailed() {
    isWorkDetailLoaded = true;
    workDetailStatsFailed = true;
  }

  /// [POSTING-V2-01B] 재시도를 위해 로드 상태를 되돌린다.
  void resetWorkDetailLoad() {
    isWorkDetailLoaded = false;
    workDetailStatsFailed = false;
  }

  void updateOuterStats({
    required int confirmed,
    required int pending,
    int? required,
  }) {
    confirmedCount = confirmed;
    pendingCount = pending;
    if (required != null) totalRequired = required;
  }

  bool get needsWorkDetailLoad => !isWorkDetailLoaded;

  /// 슬롯 날짜 (flex only)
  DateTime? get slotDate => slot?.date;

  /// 슬롯 날짜가 오늘 이전인지 여부
  bool get isSlotDatePast => slot?.isDatePast ?? false;

  // ── 통계 집계 ────────────────────────────────────────────

  /// workDetailStats 로드 여부에 따라 최적 집계 반환 — 카드 표시용
  ///
  /// - workDetails 로드됨: workDetailStats 기준 (업무유형별 정확한 수치)
  /// - 미로드: slot 수준 confirmedCount/pendingCount 사용
  /// [R7-P1-PRODUCT §9] `shortage`가 추가됐다 — **업무별로 세어 더한다.**
  ///
  ///   `required − confirmed`를 집계 수준에서 계산하면 과충원된 업무가 다른
  ///   업무의 부족을 상쇄한다. 필요 3에 5명 확정된 업무와 필요 3에 0명인
  ///   업무가 같이 있으면 합산식은 `6 − 5 = 1`이라고 말하지만 실제로는
  ///   3명이 모자란다. 그래서 업무마다 clamp한 뒤 더한다
  ///   (DayApplicantsDialog·callableGetStaffingReadiness와 같은 규칙).
  ///
  ///   업무별로 가를 수 없는 폴백 경로에서는 슬롯 카운터로만 계산한다 —
  ///   그 경로에는 애초에 업무별 수치가 없다.
  ({int confirmed, int pending, int required, int shortage}) resolveStats() {
    int clamp(int n) => n > 0 ? n : 0;
    // [POSTING-V2-01B] 통계 조회가 실패했으면 전부 0인 workDetailStats를 쓰지 않는다.
    // 슬롯 문서의 denormalized counter는 별도 source라 그대로 유효하다 — 이쪽으로 폴백.
    if (workDetailStatsFailed) {
      return (
        confirmed: confirmedCount,
        pending: pendingCount,
        required: totalRequired,
        shortage: clamp(totalRequired - confirmedCount),
      );
    }
    // [R7-P1-2 DEVICE.1D] 요약과 업무 상세가 같은 집계를 본다.
    //
    //   여기는 `isWorkDetailLoaded && workDetails.isNotEmpty` 를 봤다.
    //   그런데 장기/단건 카드가 만드는 합성 TOItem 은 `workDetailStats` 와
    //   `isWorkDetailLoaded` 만 넘기고 **workDetails 는 넘기지 않는다**.
    //   그래서 집계가 손에 있는데도 조건이 false 가 되어 카운터로 떨어졌다.
    //
    //   같은 카드의 업무 상세는 `_getSingleTOWorkDetails()` 로
    //   `slot → TOItem → 마스터 TO` 까지 폴백해 언제나 업무 목록을 얻는다.
    //   한 화면이 "업무 상세가 있는가"를 두 기준으로 판정하고 있었다 —
    //   그래서 카운터가 뒤처지는 모든 순간에 두 숫자가 갈라졌다.
    //
    //   판정을 그쪽에 맞춘다. 그리고 기준을 flag 가 아니라 **집계의 존재**로
    //   바꾼다 — `isWorkDetailLoaded` 는 업무 정의 로드 여부이고, 우리가
    //   묻는 것은 통계가 있느냐다.
    final details = workDetails.isNotEmpty ? workDetails : to.workDetails;
    if (workDetailStats != null && details.isNotEmpty) {
      var c = 0, p = 0, r = 0, s = 0;
      for (final work in details) {
        final stats = work.lookupByIdentity(workDetailStats);
        final wc = (stats?['confirmed'] ?? 0);
        c += wc;
        p += (stats?['pending'] ?? 0);
        r += work.requiredCount;
        s += clamp(work.requiredCount - wc);
      }
      return (confirmed: c, pending: p, required: r, shortage: s);
    }
    return (
      confirmed: confirmedCount,
      pending: pendingCount,
      required: totalRequired,
      shortage: clamp(totalRequired - confirmedCount),
    );
  }

  /// [R7-P1-2 DEVICE.1D] 지금 말하는 수치가 **집계에서 나온 것**인가.
  ///
  ///   false 면 카운터 폴백이다 — 같은 카드의 업무 상세는 그 상태를
  ///   `모름 + 다시 시도` 로 그린다. 두 표면이 서로 다른 확신도로 같은
  ///   metric 을 말하지 않도록, 화면이 이 값을 보고 맞춘다.
  ///   (UNKNOWN != ZERO — 집계가 없다고 0 이라고 말하지 않는다)
  bool get hasLoadedStats {
    if (workDetailStatsFailed) return false;
    final details = workDetails.isNotEmpty ? workDetails : to.workDetails;
    return workDetailStats != null && details.isNotEmpty;
  }

  /// workDetailStats 기준 인원 충족 여부
  bool get resolvedIsFull {
    final s = resolveStats();
    return s.required > 0 && s.confirmed >= s.required;
  }
}
