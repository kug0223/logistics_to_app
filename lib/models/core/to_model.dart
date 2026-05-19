import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../utils/format_helper.dart';
import 'work_detail_data.dart';

/// 공고(TO) 모델 — slots 구조 기반
///
/// type: 'flex'     단기 일용직. 날짜별 SlotModel 서브컬렉션으로 관리.
/// type: 'contract' 장기 계약직. 날짜 슬롯 없이 공고 단위로 지원자 관리.
///
/// workDetails: 배열 필드로 TO 문서에 직접 저장 (별도 서브컬렉션 없음).
class TOModel {
  final String id;

  // ── 사업장 ────────────────────────────────────────
  final String businessId;
  final String businessName;
  final String? businessAddress;
  final String? businessCity;
  final String? businessDistrict;

  // ── 공고 유형 ─────────────────────────────────────
  /// 'flex' (단기) | 'contract' (장기)
  final String type;

  // ── 기본 정보 ─────────────────────────────────────
  final String title;
  final String? groupTitle; // 관리자용 카드 제목 (null이면 title 사용)
  final String? description;

  // ── 업무 상세 (배열, 문서 내 저장) ────────────────
  final List<WorkDetailData> workDetails;

  // ── flex 전용 집계 ────────────────────────────────
  /// 등록된 슬롯(날짜) 수
  final int totalSlots;

  // ── contract 전용 ─────────────────────────────────
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final List<String> workDays; // ['월', '화', ...]
  final String deadlineType;   // 'HOURS_BEFORE' | 'FIXED_TIME'
  final int? hoursBeforeStart;
  final DateTime? applicationDeadline; // contract: 공고 마감일

  // ── 인원 집계 ─────────────────────────────────────
  final int totalRequired;
  final int totalConfirmed;
  final int totalPending;

  // ── 상태 ─────────────────────────────────────────
  final String status; // 'ACTIVE' | 'CLOSED' | 'FULL' | 'EXPIRED' | 'SCHEDULED'
  final DateTime? statusUpdatedAt;
  final bool isManualClosed;
  final DateTime? closedAt;
  final String? closedBy;
  final DateTime? reopenedAt;
  final String? reopenedBy;

  // ── 예약 공개 ─────────────────────────────────────
  final String publishMode; // 'immediate' | 'scheduled'
  final DateTime? publishAt;
  final bool isPublished;
  final int? publishDaysBefore;
  final String? publishTime;

  // ── 메타 ─────────────────────────────────────────
  final String creatorUID;
  final DateTime createdAt;

  TOModel({
    required this.id,
    required this.businessId,
    required this.businessName,
    this.businessAddress,
    this.businessCity,
    this.businessDistrict,
    this.type = 'flex',
    required this.title,
    this.groupTitle,
    this.description,
    this.workDetails = const [],
    this.totalSlots = 0,
    this.rangeStart,
    this.rangeEnd,
    this.workDays = const [],
    this.deadlineType = 'HOURS_BEFORE',
    this.hoursBeforeStart = 2,
    this.applicationDeadline,
    this.totalRequired = 0,
    this.totalConfirmed = 0,
    this.totalPending = 0,
    this.status = TOStatus.active,
    this.statusUpdatedAt,
    this.isManualClosed = false,
    this.closedAt,
    this.closedBy,
    this.reopenedAt,
    this.reopenedBy,
    this.publishMode = 'immediate',
    this.publishAt,
    this.isPublished = true,
    this.publishDaysBefore,
    this.publishTime,
    required this.creatorUID,
    required this.createdAt,
  });

  // ── 직렬화 ────────────────────────────────────────

  factory TOModel.fromMap(Map<String, dynamic> data, String documentId) {
    return TOModel(
      id: documentId,
      businessId: data['businessId'] as String? ?? '',
      businessName: data['businessName'] as String? ?? '',
      businessAddress: data['businessAddress'] as String?,
      businessCity: data['businessCity'] as String?,
      businessDistrict: data['businessDistrict'] as String?,
      type: data['type'] as String? ?? 'flex',
      title: data['title'] as String? ?? '제목 없음',
      groupTitle: data['groupTitle'] as String?,
      description: data['description'] as String?,
      workDetails: WorkDetailData.listFromFirestore(data['workDetails']),
      totalSlots: data['totalSlots'] as int? ?? 0,
      rangeStart: (data['rangeStart'] as Timestamp?)?.toDate(),
      rangeEnd: (data['rangeEnd'] as Timestamp?)?.toDate(),
      workDays: data['workDays'] != null
          ? List<String>.from(data['workDays'] as List)
          : const [],
      deadlineType: data['deadlineType'] as String? ?? 'HOURS_BEFORE',
      hoursBeforeStart: data['hoursBeforeStart'] as int? ?? 2,
      applicationDeadline:
          (data['applicationDeadline'] as Timestamp?)?.toDate().toLocal(),
      totalRequired: data['totalRequired'] as int? ?? 0,
      totalConfirmed: data['totalConfirmed'] as int? ?? 0,
      totalPending: data['totalPending'] as int? ?? 0,
      status: data['status'] as String? ?? TOStatus.active,
      statusUpdatedAt: (data['statusUpdatedAt'] as Timestamp?)?.toDate(),
      isManualClosed: data['isManualClosed'] as bool? ?? false,
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      closedBy: data['closedBy'] as String?,
      reopenedAt: (data['reopenedAt'] as Timestamp?)?.toDate(),
      reopenedBy: data['reopenedBy'] as String?,
      publishMode: data['publishMode'] as String? ?? 'immediate',
      publishAt: (data['publishAt'] as Timestamp?)?.toDate().toLocal(),
      isPublished: data['isPublished'] as bool? ?? true,
      publishDaysBefore: data['publishDaysBefore'] as int?,
      publishTime: data['publishTime'] as String?,
      creatorUID: data['creatorUID'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'businessId': businessId,
      'businessName': businessName,
      'businessAddress': businessAddress,
      'businessCity': businessCity,
      'businessDistrict': businessDistrict,
      'type': type,
      'title': title,
      if (groupTitle != null && groupTitle!.isNotEmpty) 'groupTitle': groupTitle,
      'description': description,
      'workDetails': WorkDetailData.listToFirestore(workDetails),
      'totalSlots': totalSlots,
      if (rangeStart != null) 'rangeStart': Timestamp.fromDate(rangeStart!),
      if (rangeEnd != null) 'rangeEnd': Timestamp.fromDate(rangeEnd!),
      'workDays': workDays,
      'deadlineType': deadlineType,
      'hoursBeforeStart': hoursBeforeStart,
      if (applicationDeadline != null)
        'applicationDeadline': Timestamp.fromDate(applicationDeadline!),
      'totalRequired': totalRequired,
      'totalConfirmed': totalConfirmed,
      'totalPending': totalPending,
      'status': status,
      if (statusUpdatedAt != null)
        'statusUpdatedAt': Timestamp.fromDate(statusUpdatedAt!),
      'isManualClosed': isManualClosed,
      if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
      'closedBy': closedBy,
      if (reopenedAt != null) 'reopenedAt': Timestamp.fromDate(reopenedAt!),
      'reopenedBy': reopenedBy,
      'publishMode': publishMode,
      if (publishAt != null) 'publishAt': Timestamp.fromDate(publishAt!),
      'isPublished': isPublished,
      'publishDaysBefore': publishDaysBefore,
      'publishTime': publishTime,
      'creatorUID': creatorUID,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  TOModel copyWith({
    String? id,
    String? businessId,
    String? businessName,
    String? businessAddress,
    String? businessCity,
    String? businessDistrict,
    String? type,
    String? title,
    String? groupTitle,
    bool clearGroupTitle = false,
    String? description,
    List<WorkDetailData>? workDetails,
    int? totalSlots,
    DateTime? rangeStart,
    DateTime? rangeEnd,
    List<String>? workDays,
    String? deadlineType,
    int? hoursBeforeStart,
    DateTime? applicationDeadline,
    int? totalRequired,
    int? totalConfirmed,
    int? totalPending,
    String? status,
    DateTime? statusUpdatedAt,
    bool? isManualClosed,
    DateTime? closedAt,
    String? closedBy,
    DateTime? reopenedAt,
    String? reopenedBy,
    String? publishMode,
    DateTime? publishAt,
    bool? isPublished,
    int? publishDaysBefore,
    String? publishTime,
    String? creatorUID,
    DateTime? createdAt,
  }) {
    return TOModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      businessAddress: businessAddress ?? this.businessAddress,
      businessCity: businessCity ?? this.businessCity,
      businessDistrict: businessDistrict ?? this.businessDistrict,
      type: type ?? this.type,
      title: title ?? this.title,
      groupTitle: clearGroupTitle ? null : (groupTitle ?? this.groupTitle),
      description: description ?? this.description,
      workDetails: workDetails ?? this.workDetails,
      totalSlots: totalSlots ?? this.totalSlots,
      rangeStart: rangeStart ?? this.rangeStart,
      rangeEnd: rangeEnd ?? this.rangeEnd,
      workDays: workDays ?? this.workDays,
      deadlineType: deadlineType ?? this.deadlineType,
      hoursBeforeStart: hoursBeforeStart ?? this.hoursBeforeStart,
      applicationDeadline: applicationDeadline ?? this.applicationDeadline,
      totalRequired: totalRequired ?? this.totalRequired,
      totalConfirmed: totalConfirmed ?? this.totalConfirmed,
      totalPending: totalPending ?? this.totalPending,
      status: status ?? this.status,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
      isManualClosed: isManualClosed ?? this.isManualClosed,
      closedAt: closedAt ?? this.closedAt,
      closedBy: closedBy ?? this.closedBy,
      reopenedAt: reopenedAt ?? this.reopenedAt,
      reopenedBy: reopenedBy ?? this.reopenedBy,
      publishMode: publishMode ?? this.publishMode,
      publishAt: publishAt ?? this.publishAt,
      isPublished: isPublished ?? this.isPublished,
      publishDaysBefore: publishDaysBefore ?? this.publishDaysBefore,
      publishTime: publishTime ?? this.publishTime,
      creatorUID: creatorUID ?? this.creatorUID,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ── 타입 헬퍼 ─────────────────────────────────────

  bool get isFlexType => type == 'flex';
  bool get isContractType => type == 'contract';

  /// 관리자 카드에 표시할 제목 (groupTitle 없으면 title 사용)
  String get displayGroupTitle =>
      (groupTitle?.isNotEmpty == true) ? groupTitle! : title;

  String get typeLabel => isFlexType ? '단기 근무' : '고정 근무';

  // ── workDetails 집계 (computed) ───────────────────

  int get workDetailCount => workDetails.length;

  int? get minWage => workDetails.isEmpty
      ? null
      : workDetails.map((d) => d.wage).reduce((a, b) => a < b ? a : b);

  int? get maxWage => workDetails.isEmpty
      ? null
      : workDetails.map((d) => d.wage).reduce((a, b) => a > b ? a : b);

  String? get wageType => workDetails.isEmpty ? null : workDetails.first.wageType;

  String get timeRange {
    if (workDetails.isEmpty) return '--:-- ~ --:--';
    final starts = workDetails.map((d) => d.startTime).toList()..sort();
    final ends = workDetails.map((d) => d.endTime).toList()..sort();
    return '${starts.first} ~ ${ends.last}';
  }

  // ── 상태 헬퍼 ─────────────────────────────────────

  bool get isFull => totalRequired > 0 && totalConfirmed >= totalRequired;
  bool get isActive => status == TOStatus.active;
  bool get isScheduledPublish => publishMode == 'scheduled';

  bool get isPendingPublish {
    if (!isScheduledPublish || isPublished || publishAt == null) return false;
    return DateTime.now().isBefore(publishAt!);
  }

  // isManualClosed는 메타데이터 (누가 닫았나)일 뿐 — 닫힘 여부는 status 필드만 사용
  bool get isClosed =>
      isFull || status == TOStatus.closed || status == TOStatus.expired;

  String get calculatedStatus {
    if (isManualClosed) return TOStatus.closed;
    if (isFull) return TOStatus.full;
    return TOStatus.active;
  }

  // ── contract 전용 ─────────────────────────────────

  String get contractPeriodDisplay {
    if (!isContractType || rangeStart == null || rangeEnd == null) return '';
    return '${FormatHelper.formatDate(rangeStart!)} ~ ${FormatHelper.formatDate(rangeEnd!)}';
  }

  String get workDaysLabel {
    if (!isContractType || workDays.isEmpty) return '';
    final count = workDays.length;
    if (count == 7) return '매일 근무';
    if (count == 6) {
      final all = ['월', '화', '수', '목', '금', '토', '일'];
      final off = all.firstWhere((d) => !workDays.contains(d));
      return '주 6일 ($off 휴무)';
    }
    if (count == 5) {
      final all = ['월', '화', '수', '목', '금', '토', '일'];
      final off = all.where((d) => !workDays.contains(d)).join(', ');
      return '주 5일 ($off 휴무)';
    }
    return '주 $count일 (${workDays.join(', ')})';
  }

  // ── 예약 공개 ─────────────────────────────────────

  String? get publishAtDisplay {
    if (publishAt == null) return null;
    return '${publishAt!.month}/${publishAt!.day} '
        '${publishAt!.hour.toString().padLeft(2, '0')}:'
        '${publishAt!.minute.toString().padLeft(2, '0')}';
  }

  // ── 인원 ─────────────────────────────────────────

  int get availableSlots => totalRequired - totalConfirmed;

  // ── 마감 상태 (contract용) ────────────────────────

  bool get isDeadlinePassed {
    if (applicationDeadline == null) return false;
    return DateTime.now().isAfter(applicationDeadline!);
  }

  String get closedReason {
    if (isManualClosed) return '수동 마감';
    if (isFull) return '인원 충족';
    return '';
  }

  @override
  String toString() =>
      'TOModel(id: $id, type: $type, title: $title, status: $status, '
      'slots: $totalSlots, workDetails: ${workDetails.length})';

  // ── 하위 호환성 getters ───────────────────────────────────────
  // 구 아키텍처(groups/date 기반)에서 마이그레이션 중인 화면에서 사용.
  // Phase 5-6 리팩터링 완료 후 제거 예정.

  /// 구 date 필드. flex: createdAt, contract: rangeStart
  DateTime get date => rangeStart ?? createdAt;

  /// isContractType 별칭
  bool get isLongTerm => isContractType;

  /// isFlexType 별칭
  bool get isShortTerm => isFlexType;

  /// rangeEnd 별칭
  DateTime? get endDate => rangeEnd;

  /// rangeStart 별칭
  DateTime? get startDate => rangeStart;

  /// type 별칭 (구 jobType)
  String get jobType => type;

  /// typeLabel 별칭 (구 jobTypeLabel)
  String get jobTypeLabel => typeLabel;

  /// MM/dd 형식 날짜
  String get formattedDate {
    final d = date;
    return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  /// 마감일 표시
  String get formattedDeadline {
    final dl = applicationDeadline;
    if (dl == null) return '-';
    return '${dl.month}/${dl.day} '
        '${dl.hour.toString().padLeft(2, '0')}:'
        '${dl.minute.toString().padLeft(2, '0')}';
  }

  /// 마감 30분 이내 여부
  bool get isDeadlineSoon {
    final dl = applicationDeadline;
    if (dl == null) return false;
    final diff = dl.difference(DateTime.now()).inMinutes;
    return diff >= 0 && diff <= 30;
  }

  /// 날짜 범위 표시 (구 groupDateRangeDisplay)
  String get groupDateRangeDisplay => contractPeriodDisplay;

  /// 마감시간 초과 여부 (구 isTimeExpired)
  bool get isTimeExpired => isDeadlinePassed;

  /// 첫 번째 업무의 시작 시간 (구 startTime)
  String get startTime {
    if (workDetails.isEmpty) return '--:--';
    final starts = workDetails.map((d) => d.startTime).toList()..sort();
    return starts.first;
  }

  /// 마지막 업무의 종료 시간 (구 endTime)
  String get endTime {
    if (workDetails.isEmpty) return '--:--';
    final ends = workDetails.map((d) => d.endTime).toList()..sort();
    return ends.last;
  }

  /// 구 그룹 시간 범위 설정 — no-op (TO는 불변 객체, 이 필드 제거됨)
  // ignore: use_setters_to_change_properties
  void setTimeRange(String? minStart, String? maxEnd) {}
}

/// TO Firestore 상태 상수 (대문자 — TO 컬렉션 convention)
abstract class TOStatus {
  static const String active    = 'ACTIVE';
  static const String closed    = 'CLOSED';
  static const String full      = 'FULL';
  static const String expired   = 'EXPIRED';
  static const String scheduled = 'SCHEDULED';

  /// 모집 중 상태 그룹 (Firestore whereIn 쿼리용)
  static const List<String> openStates   = [active, full, scheduled];
  /// 마감 상태 그룹
  static const List<String> closedStates = [closed, expired];
}
