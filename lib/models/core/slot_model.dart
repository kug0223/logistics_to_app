import 'package:cloud_firestore/cloud_firestore.dart';
import 'work_detail_data.dart';
import '../../utils/format_helper.dart';

/// 슬롯 내 업무유형별 지원 현황 (key: workType)
class SlotWorkTypeCount {
  final int confirmedCount;
  final int pendingCount;

  const SlotWorkTypeCount({
    this.confirmedCount = 0,
    this.pendingCount = 0,
  });

  factory SlotWorkTypeCount.fromMap(Map<String, dynamic> map) {
    return SlotWorkTypeCount(
      confirmedCount: map['confirmedCount'] as int? ?? 0,
      pendingCount: map['pendingCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'confirmedCount': confirmedCount,
    'pendingCount': pendingCount,
  };

  SlotWorkTypeCount copyWith({int? confirmedCount, int? pendingCount}) {
    return SlotWorkTypeCount(
      confirmedCount: confirmedCount ?? this.confirmedCount,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }
}

/// flex 타입 공고의 날짜별 슬롯 모델
///
/// Firestore 경로: tos/{toId}/slots/{slotId}
///
/// 각 슬롯은 독립적인 날짜를 나타내며, workDetails(업무 정의)와
/// workTypeCounts(업무유형별 지원 현황)를 날짜별로 독립 관리한다.
class SlotModel {
  final String id;
  final String toId;
  final DateTime date;

  /// 슬롯 고유의 업무 목록 — 공고 생성 시 TO 템플릿 복사, 날짜별 수정 가능
  /// 급여·근무시간·필요인원 모두 날짜별로 다르게 설정 가능
  final List<WorkDetailData> workDetails;

  /// 업무유형별 지원 현황 (key: workType)
  /// 지원 처리 시 incrementally 업데이트됨
  final Map<String, SlotWorkTypeCount> workTypeCounts;

  /// 'open' | 'full' | 'closed'
  final String status;

  final int confirmedCount; // 전체 합계
  final int pendingCount;   // 전체 합계

  /// 지원 마감 시각
  final DateTime? applicationDeadline;

  /// 슬롯 공개 시각 — 이 시각이 지나야 유저 화면에 노출
  /// null 이면 즉시 공개 (publishMode == 'immediate')
  final DateTime? visibleFrom;

  final String? title; // 날짜별 공고 제목 (null이면 마스터 TO title 사용)
  final bool isManualClosed;
  final DateTime? closedAt;
  final String? closedBy;
  final DateTime? reopenedAt;
  final String? reopenedBy;

  final DateTime createdAt;

  const SlotModel({
    required this.id,
    required this.toId,
    required this.date,
    this.workDetails = const [],
    this.workTypeCounts = const {},
    this.status = SlotStatus.open,
    this.confirmedCount = 0,
    this.pendingCount = 0,
    this.applicationDeadline,
    this.visibleFrom,
    this.title,
    this.isManualClosed = false,
    this.closedAt,
    this.closedBy,
    this.reopenedAt,
    this.reopenedBy,
    required this.createdAt,
  });

  factory SlotModel.fromMap(Map<String, dynamic> data, String documentId, String toId) {
    final workDetails = WorkDetailData.listFromFirestore(data['workDetails']);

    final rawCounts = data['workTypeCounts'] as Map<String, dynamic>?;
    final workTypeCounts = rawCounts != null
        ? rawCounts.map((k, v) => MapEntry(
            k, SlotWorkTypeCount.fromMap(Map<String, dynamic>.from(v as Map))))
        : <String, SlotWorkTypeCount>{};

    return SlotModel(
      id: documentId,
      toId: toId,
      date: (data['date'] as Timestamp).toDate(),
      workDetails: workDetails,
      workTypeCounts: workTypeCounts,
      status: data['status'] as String? ?? SlotStatus.open,
      confirmedCount: data['confirmedCount'] as int? ?? 0,
      pendingCount: data['pendingCount'] as int? ?? 0,
      applicationDeadline:
          (data['applicationDeadline'] as Timestamp?)?.toDate().toLocal(),
      visibleFrom: (data['visibleFrom'] as Timestamp?)?.toDate().toLocal(),
      title: data['title'] as String?,
      isManualClosed: data['isManualClosed'] as bool? ?? false,
      closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
      closedBy: data['closedBy'] as String?,
      reopenedAt: (data['reopenedAt'] as Timestamp?)?.toDate(),
      reopenedBy: data['reopenedBy'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'toId': toId,
      'date': Timestamp.fromDate(date),
      'workDetails': WorkDetailData.listToFirestore(workDetails),
      'workTypeCounts': workTypeCounts.map((k, v) => MapEntry(k, v.toMap())),
      'status': status,
      'confirmedCount': confirmedCount,
      'pendingCount': pendingCount,
      if (applicationDeadline != null)
        'applicationDeadline': Timestamp.fromDate(applicationDeadline!),
      if (visibleFrom != null)
        'visibleFrom': Timestamp.fromDate(visibleFrom!.toUtc()),
      if (title != null && title!.isNotEmpty) 'title': title,
      'isManualClosed': isManualClosed,
      if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
      'closedBy': closedBy,
      if (reopenedAt != null) 'reopenedAt': Timestamp.fromDate(reopenedAt!),
      'reopenedBy': reopenedBy,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  SlotModel copyWith({
    String? id,
    String? toId,
    DateTime? date,
    List<WorkDetailData>? workDetails,
    Map<String, SlotWorkTypeCount>? workTypeCounts,
    String? status,
    int? confirmedCount,
    int? pendingCount,
    DateTime? applicationDeadline,
    DateTime? visibleFrom,
    bool clearVisibleFrom = false,
    String? title,
    bool clearTitle = false,
    bool? isManualClosed,
    DateTime? closedAt,
    String? closedBy,
    DateTime? reopenedAt,
    String? reopenedBy,
    DateTime? createdAt,
  }) {
    return SlotModel(
      id: id ?? this.id,
      toId: toId ?? this.toId,
      date: date ?? this.date,
      workDetails: workDetails ?? this.workDetails,
      workTypeCounts: workTypeCounts ?? this.workTypeCounts,
      status: status ?? this.status,
      confirmedCount: confirmedCount ?? this.confirmedCount,
      pendingCount: pendingCount ?? this.pendingCount,
      applicationDeadline: applicationDeadline ?? this.applicationDeadline,
      visibleFrom: clearVisibleFrom ? null : (visibleFrom ?? this.visibleFrom),
      title: clearTitle ? null : (title ?? this.title),
      isManualClosed: isManualClosed ?? this.isManualClosed,
      closedAt: closedAt ?? this.closedAt,
      closedBy: closedBy ?? this.closedBy,
      reopenedAt: reopenedAt ?? this.reopenedAt,
      reopenedBy: reopenedBy ?? this.reopenedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ── 헬퍼 ──────────────────────────────────────────

  bool get isOpen => status == SlotStatus.open;
  bool get isFull => status == SlotStatus.full;
  // isManualClosed는 메타데이터 — 닫힘 여부는 status만 사용
  bool get isClosed => status == SlotStatus.closed;

  /// 슬롯 날짜(date)가 오늘 이전인지 여부
  bool get isDatePast {
    final today = DateTime.now();
    return DateTime(date.year, date.month, date.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }

  /// 수동마감·CF마감·인원충족·날짜경과 중 하나라도 해당하면 true (UI 상태 표시용)
  bool get isEffectivelyClosed => isClosed || isFull || isDatePast;

  bool get isDeadlinePassed {
    if (applicationDeadline == null) return false;
    return DateTime.now().isAfter(applicationDeadline!);
  }

  /// 전체 필요 인원 (workDetails.requiredCount 합계)
  int get totalRequired =>
      workDetails.fold(0, (acc, d) => acc + d.requiredCount);

  /// 특정 업무유형의 지원 현황
  SlotWorkTypeCount countFor(String workType) =>
      workTypeCounts[workType] ?? const SlotWorkTypeCount();

  /// 특정 업무유형이 마감됐는지 (confirmedCount >= requiredCount)
  bool isWorkTypeFull(String workType) {
    final detail = workDetails.where((d) => d.workType == workType).firstOrNull;
    if (detail == null || detail.requiredCount == 0) return false;
    return countFor(workType).confirmedCount >= detail.requiredCount;
  }

  /// 날짜 포맷 (예: "5/6 (수)")
  String get formattedDate => FormatHelper.formatDate(date);

  /// 요일 (예: "수")
  String get weekday => FormatHelper.weekday(date);

  @override
  String toString() =>
      'SlotModel(id: $id, date: ${date.toIso8601String().substring(0, 10)}, '
      'status: $status, confirmed: $confirmedCount, pending: $pendingCount)';
}

/// Slot Firestore 상태 상수 (소문자 — slots 컬렉션 convention)
abstract class SlotStatus {
  static const String open   = 'open';
  static const String full   = 'full';
  static const String closed = 'closed';
}
