// [SYSTEM-INTEGRATION-R2] 하루치 FLEX 모집 단위(wdId) 한 줄.
//
// 부족은 지원서가 아니라 slot capacity에 속한다. 지원자가 0명인 모집 단위도
// 부족으로 존재하므로, 지원서에서 유도하면 그 부족은 화면에서 사라진다.
// 이 모델은 callableGetDayStaffingDetail이 slot에서 직접 읽어 준 canonical row다.

class DayStaffingRow {
  final String toId;
  final String toTitle;
  final String slotId;
  final String wdId;
  final String workType;
  final String startTime;
  final String endTime;
  final int requiredCount;
  final int confirmedCount;
  final int pendingCount;

  /// [R2 FINAL] 이 모집 단위가 종료됐는가 — 정원이 찬 것과 다르다.
  ///
  ///   `필요 5 · 확정 2 · 관리자가 마감` 은 `모두 찼다`가 아니라
  ///   `더 이상 뽑지 않는다`다. 충원 대상에서는 빠지지만, 이유는 다르게 말한다.
  final bool isClosed;

  /// [R7-P1-PRODUCT] 장기(고정) 공고의 모집 단위인가.
  ///
  /// 장기에는 슬롯이라는 개념이 없어 [slotId]가 빈 문자열이다. 그것은
  /// "식별할 수 없다"가 아니라 "그런 것이 존재하지 않는다"는 뜻이다 —
  /// 장기의 canonical target은 `toId × wdId`다.
  final bool isLongTerm;

  /// [R7-P1R §14] 장기 초대가 만들어야 하는 약속의 범위.
  ///
  /// 장기 초대는 하루가 아니라 **기간**에 대한 제안이다. 이 둘이 없으면
  /// 서버는 하루짜리 지원서를 만든다 — 그래서 장기 CTA를 막아 두었다.
  /// 클라이언트가 TO를 따로 읽어 조립하지 않는다. 이 row를 만든 reader가
  /// 이미 TO를 읽었으므로 그쪽이 canonical source다.
  ///
  /// 단기에서는 null / 빈 목록이다 — 그 개념이 없다.
  final DateTime? workEndDate;
  final List<String> workDays;

  const DayStaffingRow({
    required this.toId,
    required this.toTitle,
    required this.slotId,
    required this.wdId,
    required this.workType,
    required this.startTime,
    required this.endTime,
    required this.requiredCount,
    required this.confirmedCount,
    required this.pendingCount,
    this.isClosed = false,
    this.isLongTerm = false,
    this.workEndDate,
    this.workDays = const [],
  });

  /// canonical shortage — 서버 staffing readiness와 같은 식.
  /// 초과 확정이 다른 모집 단위의 부족을 상쇄하지 않도록 음수는 0으로 막는다.
  ///
  /// 종료된 모집 단위는 부족이 아니다 — 채울 대상이 아니기 때문이다.
  int get shortage => isClosed
      ? 0
      : (requiredCount - confirmedCount > 0
          ? requiredCount - confirmedCount
          : 0);

  static DayStaffingRow? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final toId = m['toId'] as String?;
    final slotId = m['slotId'] as String?;
    final wdId = m['wdId'] as String?;
    final isLongTerm = m['isLongTerm'] == true;
    if (toId == null || toId.isEmpty) return null;
    // [R7-P1-PRODUCT] slotId 비어 있음을 버리는 조건이었다.
    //   단기에서는 슬롯 없는 row가 곧 깨진 데이터지만, 장기에는 슬롯이
    //   **애초에 없다**. 그래서 서버가 장기 row를 보내기 시작하면 여기서
    //   전부 버려져, 고친 집계가 화면에 닿지 못한다.
    if (!isLongTerm && (slotId == null || slotId.isEmpty)) return null;
    // [R7-P1R] wdId 비어 있음을 버리는 조건이었다.
    //
    //   장기 공고의 TO.workDetails에는 wdId가 없는 레코드가 있다(DEV 실측:
    //   3건 전부). 서버가 장기 row를 보내기 시작한 뒤에도 여기서 전부
    //   버려져, 고친 집계가 화면에 닿지 못했다 — 1차 검증은 스크립트가
    //   서버 응답을 직접 읽어 통과한 것이라 이 층을 지나지 않았다.
    //
    //   단기는 그대로 거부한다. FLEX 슬롯의 workDetails에는 wdId가 항상
    //   있고(없으면 서버가 WORKDETAIL_CONTRACT_BROKEN으로 던진다),
    //   그 자리의 빈 wdId는 곧 깨진 데이터다.
    //
    //   장기는 코드베이스가 이미 쓰는 fallback 식별자로 대체한다 —
    //   `workType_startTime_endTime`. WorkDetailData.id·_GroupData.groupKey·
    //   loadTOWorkDetails의 workStats 키가 모두 같은 형식을 쓴다.
    //   새 identity를 만드는 것이 아니라 있는 것을 따른다.
    if (!isLongTerm && (wdId == null || wdId.isEmpty)) return null;
    final workType = (m['workType'] as String?) ?? '';
    final startTime = (m['startTime'] as String?) ?? '';
    final endTime = (m['endTime'] as String?) ?? '';
    // wdId가 없으면 코드베이스 공통 fallback 식별자를 쓴다.
    final effectiveWdId = (wdId != null && wdId.isNotEmpty)
        ? wdId
        : '${workType}_${startTime}_$endTime';
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return DayStaffingRow(
      toId: toId,
      toTitle: (m['toTitle'] as String?) ?? '',
      slotId: slotId ?? '',
      wdId: effectiveWdId,
      workType: workType,
      startTime: startTime,
      endTime: endTime,
      requiredCount: n('requiredCount'),
      confirmedCount: n('confirmedCount'),
      pendingCount: n('pendingCount'),
      isClosed: m['isClosed'] == true,
      isLongTerm: isLongTerm,
      workEndDate: (m['workEndDateMs'] as num?) == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              (m['workEndDateMs'] as num).toInt()),
      workDays: ((m['workDays'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}
