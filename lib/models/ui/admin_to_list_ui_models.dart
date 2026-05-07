import '../core/to_model.dart';
import '../core/slot_model.dart';
import '../core/work_detail_data.dart';

/// 공고 리스트 아이템 (관리자용)
///
/// 단일 TOModel을 래핑. flex 타입은 slots를 lazy-load.
/// [Phase 3 리팩토링] groups 구조 제거, slots 구조로 전환.
class TOGroupItem {
  /// 공고 모델 (항상 non-null)
  final TOModel? singleTO;

  // flex 타입 슬롯 목록 (lazy-load)
  List<TOItem>? _groupTOs;
  bool isGroupDetailLoaded;

  // 단건 TO 업무 상세 통계 (lazy-load)
  Map<String, Map<String, int>>? workDetailStats;
  bool isWorkDetailLoaded = false;

  // 캐시된 통계 (UI 갱신용)
  int? _cachedTotalConfirmed;
  int? _cachedTotalPending;
  int? _cachedTotalRequired;

  TOGroupItem({
    this.singleTO,
    List<TOItem>? groupTOs,
    this.isGroupDetailLoaded = false,
  }) : _groupTOs = groupTOs {
    assert(singleTO != null, 'singleTO is required');
  }

  void setWorkDetailStats(Map<String, Map<String, int>> stats) {
    workDetailStats = stats;
    isWorkDetailLoaded = true;
  }

  // ── 기본 정보 ──────────────────────────────────────────

  bool get isGrouped => false;
  String get id => singleTO!.id;
  String get title => singleTO!.title;
  String get businessName => singleTO!.businessName;
  String get businessId => singleTO!.businessId;
  String get status => singleTO!.status;
  bool get isClosed => singleTO!.isClosed;
  bool get isManualClosed => singleTO!.isManualClosed;
  bool get isPendingPublish => singleTO!.isPendingPublish;
  DateTime? get publishAt => singleTO!.publishAt;

  /// contract 타입 여부 (구 isLongTerm)
  bool get isLongTerm => singleTO!.isContractType;

  // ── 통계 ─────────────────────────────────────────────

  int get totalRequired =>
      _cachedTotalRequired ?? singleTO!.totalRequired;
  int get totalConfirmed =>
      _cachedTotalConfirmed ?? singleTO!.totalConfirmed;
  int get totalPending =>
      _cachedTotalPending ?? singleTO!.totalPending;
  bool get isFull => singleTO!.isFull;

  // ── 날짜 ─────────────────────────────────────────────

  /// 시작일. flex: 첫 슬롯 날짜 또는 createdAt; contract: rangeStart
  DateTime get startDate =>
      singleTO!.rangeStart ?? singleTO!.createdAt;

  /// 종료일. flex: 마지막 슬롯 날짜 또는 createdAt; contract: rangeEnd
  DateTime get endDate =>
      singleTO!.rangeEnd ?? singleTO!.createdAt;

  /// 날짜 범위 문자열
  String get dateRangeString {
    if (singleTO!.isFlexType) {
      final count = singleTO!.totalSlots;
      return count > 0 ? '$count일' : '';
    }
    return singleTO!.contractPeriodDisplay;
  }

  // ── 급여 ─────────────────────────────────────────────

  int? get minWage => singleTO!.minWage;
  int? get maxWage => singleTO!.maxWage;
  String? get wageType => singleTO!.wageType;

  // ── 기타 ─────────────────────────────────────────────

  /// 표시명 (구 groupName)
  String get groupName => singleTO!.title;
  DateTime get createdAt => singleTO!.createdAt;
  String? get description => singleTO!.description;
  String get creatorUID => singleTO!.creatorUID;

  /// flex: 슬롯 수; contract: 1
  int get actualDaysCount =>
      singleTO!.isFlexType ? singleTO!.totalSlots : 1;

  int get workDetailCount => singleTO!.workDetailCount;

  // ── TOItem 목록 (flex 전용 날짜별 아이템) ─────────────

  List<TOItem> get groupTOs => _groupTOs ?? [];

  void setGroupTOs(List<TOItem> items) {
    _groupTOs = items;
    isGroupDetailLoaded = true;
  }

  bool get needsGroupDetailLoad => false;

  /// 공고 모델 직접 접근
  TOModel get masterTO => singleTO!;

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

  TOItem({
    required this.to,
    this.slot,
    List<WorkDetailData>? workDetails,
    required this.confirmedCount,
    required this.pendingCount,
    required this.totalRequired,
    this.workDetailStats,
    this.isWorkDetailLoaded = false,
  }) : _workDetails = workDetails;

  List<WorkDetailData> get workDetails => _workDetails ?? [];

  void setWorkDetails(
    List<WorkDetailData> details,
    Map<String, Map<String, int>> stats,
  ) {
    _workDetails = details;
    workDetailStats = stats;
    isWorkDetailLoaded = true;
    int totalConfirmed = 0;
    int totalPending = 0;
    for (final stat in stats.values) {
      totalConfirmed += stat['confirmed'] ?? 0;
      totalPending += stat['pending'] ?? 0;
    }
    confirmedCount = totalConfirmed;
    pendingCount = totalPending;
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
}
