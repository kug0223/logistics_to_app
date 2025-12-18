import '../core/to_model.dart';
import '../core/work_detail_model.dart';
import '../core/group_model.dart';

/// 리스트 아이템 (그룹 또는 단일 TO)
/// 
/// 🔄 리팩토링: 그룹 정보가 groups 컬렉션으로 분리됨
/// - 그룹인 경우: group 필드 사용
/// - 단일 TO인 경우: singleTO 필드 사용
class TOGroupItem {
  // ✅ 새 구조: 그룹 정보 (groups 컬렉션)
  final GroupModel? group;
  
  // ✅ 단일 TO (비그룹)
  final TOModel? singleTO;
  
  // ✨ Lazy Loading 지원
  List<TOItem>? _groupTOs;  // 그룹 내 TO 목록
  bool isGroupDetailLoaded;  // 그룹 상세(개별 TO 목록) 로드 여부

  TOGroupItem({
    this.group,
    this.singleTO,
    List<TOItem>? groupTOs,
    this.isGroupDetailLoaded = false,
  }) : _groupTOs = groupTOs {
    // 둘 중 하나는 반드시 있어야 함
    assert(group != null || singleTO != null, 'group 또는 singleTO 중 하나는 필수');
  }
  
  // ═══════════════════════════════════════════════════════════
  // Getter - 공통 정보
  // ═══════════════════════════════════════════════════════════
  
  /// 그룹 여부
  bool get isGrouped => group != null;
  
  /// 고유 ID (그룹 ID 또는 TO ID)
  String get id => group?.id ?? singleTO!.id;
  
  /// 표시 제목
  String get title => group?.title ?? singleTO!.title;
  
  /// 사업장명
  String get businessName => group?.businessName ?? singleTO!.businessName;
  
  /// 사업장 ID
  String get businessId => group?.businessId ?? singleTO!.businessId;
  
  /// 상태 (ACTIVE, CLOSED, EXPIRED, SCHEDULED)
  String get status => group?.status ?? singleTO!.status;
  
  /// 마감 여부
  bool get isClosed => group?.isClosed ?? singleTO!.isClosed;
  
  /// 수동 마감 여부
  bool get isManualClosed => group?.isManualClosed ?? singleTO!.isManualClosed;
  
  /// 예약 공개 대기 여부
  bool get isPendingPublish => group?.isPendingPublish ?? singleTO!.isPendingPublish;
  
  /// 공개 예정 시간
  DateTime? get publishAt => group?.publishAt ?? singleTO!.publishAt;
  
  /// 장기 공고 여부
  bool get isLongTerm => singleTO?.isLongTerm ?? false;
  
  // ═══════════════════════════════════════════════════════════
  // Getter - 통계
  // ═══════════════════════════════════════════════════════════
  
  /// 총 필요 인원
  int get totalRequired => group?.totalRequired ?? singleTO!.totalRequired;
  
  /// 총 확정 인원
  int get totalConfirmed => group?.totalConfirmed ?? singleTO!.totalConfirmed;
  
  /// 총 대기 인원
  int get totalPending => group?.totalPending ?? singleTO!.totalPending;
  
  /// 인원 충족 여부
  bool get isFull => group?.isFull ?? singleTO!.isFull;
  
  // ═══════════════════════════════════════════════════════════
  // Getter - 날짜/시간
  // ═══════════════════════════════════════════════════════════
  
  /// 시작일
  DateTime get startDate => group?.startDate ?? singleTO!.date;
  
  /// 종료일
  DateTime get endDate => group?.endDate ?? singleTO!.date;
  
  /// 날짜 범위 문자열
  String get dateRangeString {
    if (group != null) {
      return group!.dateRangeString;
    }
    return singleTO!.formattedDate;
  }
  
  // ═══════════════════════════════════════════════════════════
  // Getter - 급여
  // ═══════════════════════════════════════════════════════════
  
  int? get minWage => group?.minWage ?? singleTO!.minWage;
  int? get maxWage => group?.maxWage ?? singleTO!.maxWage;
  String? get wageType => group?.wageType ?? singleTO!.wageType;
  
  // ═══════════════════════════════════════════════════════════
  // Getter - 그룹 TO 목록
  // ═══════════════════════════════════════════════════════════
  
  List<TOItem> get groupTOs => _groupTOs ?? [];
  
  /// 그룹 상세 설정 (로드 후 호출)
  void setGroupTOs(List<TOItem> items) {
    _groupTOs = items;
    isGroupDetailLoaded = true;
  }
  
  /// 로드 필요 여부
  bool get needsGroupDetailLoad => isGrouped && !isGroupDetailLoaded;
  
  // ═══════════════════════════════════════════════════════════
  // 🔄 하위 호환성 - masterTO (deprecated, 점진적 제거 예정)
  // ═══════════════════════════════════════════════════════════
  
  /// @deprecated - group 또는 singleTO 사용 권장
  /// 기존 코드 호환용: 그룹이면 가상 TOModel 생성, 아니면 singleTO
  TOModel get masterTO {
    // 단일 TO인 경우
    if (singleTO != null) return singleTO!;
    
    // 그룹 TO 상세가 로드된 경우
    if (_groupTOs != null && _groupTOs!.isNotEmpty) {
      return _groupTOs!.first.to;
    }
    
    // 그룹인데 상세 로드 안 된 경우: GroupModel에서 가상 TOModel 생성
    if (group != null) {
      return TOModel(
        id: group!.id,
        businessId: group!.businessId,
        businessName: group!.businessName,
        businessAddress: group!.businessAddress,
        businessCity: group!.businessCity,
        businessDistrict: group!.businessDistrict,
        groupId: group!.id,
        groupName: group!.groupName,
        startDate: group!.startDate,
        endDate: group!.endDate,
        isGroupMaster: true,
        title: group!.title,
        date: group!.startDate,  // 그룹 시작일
        startTime: '',
        endTime: '',
        applicationDeadline: group!.publishAt ?? group!.startDate,
        totalRequired: group!.totalRequired,
        totalConfirmed: group!.totalConfirmed,
        totalPending: group!.totalPending,
        minWage: group!.minWage,
        maxWage: group!.maxWage,
        wageType: group!.wageType,
        workDetailCount: group!.workDetailCount,
        groupTotalRequired: group!.totalRequired,
        groupTotalConfirmed: group!.totalConfirmed,
        groupTotalPending: group!.totalPending,
        groupActualDaysCount: group!.actualDaysCount,
        description: group!.description,
        creatorUID: group!.creatorUID,
        createdAt: group!.createdAt,
        status: group!.status,
        statusUpdatedAt: group!.statusUpdatedAt,
        isManualClosed: group!.isManualClosed,
        closedAt: group!.closedAt,
        closedBy: group!.closedBy,
        reopenedAt: group!.reopenedAt,
        reopenedBy: group!.reopenedBy,
        publishMode: group!.publishMode,
        publishAt: group!.publishAt,
        isPublished: group!.isPublished,
        publishDaysBefore: group!.publishDaysBefore,
        publishTime: group!.publishTime,
      );
    }
    
    // Fallback: 여기 도달하면 안 됨
    throw StateError('TOGroupItem에 유효한 데이터가 없습니다');
  }
  
  // ═══════════════════════════════════════════════════════════
  // 통계 업데이트
  // ═══════════════════════════════════════════════════════════
  
  /// 그룹 통계 업데이트 (DB에서 새로 조회 후)
  void updateGroupStats({
    required int confirmed,
    required int pending,
    int? required,
  }) {
    // group은 immutable이므로 _groupTOs의 통계 업데이트
    if (_groupTOs != null && _groupTOs!.isNotEmpty) {
      // 첫 번째 아이템에 합산 통계 저장 (표시용)
      _groupTOs!.first.updateOuterStats(
        confirmed: confirmed,
        pending: pending,
        required: required,
      );
    }
  }
}

/// TO 아이템 (TO + WorkDetails + 통계)
class TOItem {
  final TOModel to;
  
  // ✨ Lazy Loading 지원
  List<WorkDetailModel>? _workDetails;  // nullable - 필요할 때 로드
  bool isWorkDetailLoaded;  // 업무 상세 로드 여부
  
  // 통계 (겉 카드용 - TO 문서에서 가져옴) - ✅ mutable
  int confirmedCount;
  int pendingCount;
  int totalRequired;
  
  // 업무별 통계 (펼쳤을 때 로드)
  Map<String, Map<String, int>>? workDetailStats;

  TOItem({
    required this.to,
    List<WorkDetailModel>? workDetails,
    required this.confirmedCount,
    required this.pendingCount,
    required this.totalRequired,
    this.workDetailStats,
    this.isWorkDetailLoaded = false,
  }) : _workDetails = workDetails;
  
  // Getter
  List<WorkDetailModel> get workDetails => _workDetails ?? [];
  
  /// 업무 상세 설정 (로드 후 호출)
  void setWorkDetails(List<WorkDetailModel> details, Map<String, Map<String, int>> stats) {
    _workDetails = details;
    workDetailStats = stats;
    isWorkDetailLoaded = true;
    
    // ✅ workStats에서 겉 카드 통계도 동기화
    int totalConfirmed = 0;
    int totalPending = 0;
    for (var stat in stats.values) {
      totalConfirmed += stat['confirmed'] ?? 0;
      totalPending += stat['pending'] ?? 0;
    }
    confirmedCount = totalConfirmed;
    pendingCount = totalPending;
  }
  
  /// 겉 카드 통계만 업데이트 (TO 문서 기준)
  void updateOuterStats({
    required int confirmed,
    required int pending,
    int? required,
  }) {
    confirmedCount = confirmed;
    pendingCount = pending;
    if (required != null) totalRequired = required;
  }
  
  /// 로드 필요 여부
  bool get needsWorkDetailLoad => !isWorkDetailLoaded;
}