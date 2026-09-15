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
  });

  /// canonical shortage — 서버 staffing readiness와 같은 식.
  /// 초과 확정이 다른 모집 단위의 부족을 상쇄하지 않도록 음수는 0으로 막는다.
  int get shortage =>
      requiredCount - confirmedCount > 0 ? requiredCount - confirmedCount : 0;

  static DayStaffingRow? tryFromMap(Object? raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final toId = m['toId'] as String?;
    final slotId = m['slotId'] as String?;
    final wdId = m['wdId'] as String?;
    if (toId == null || toId.isEmpty) return null;
    if (slotId == null || slotId.isEmpty) return null;
    if (wdId == null || wdId.isEmpty) return null;
    int n(String k) => (m[k] as num?)?.toInt() ?? 0;
    return DayStaffingRow(
      toId: toId,
      toTitle: (m['toTitle'] as String?) ?? '',
      slotId: slotId,
      wdId: wdId,
      workType: (m['workType'] as String?) ?? '',
      startTime: (m['startTime'] as String?) ?? '',
      endTime: (m['endTime'] as String?) ?? '',
      requiredCount: n('requiredCount'),
      confirmedCount: n('confirmedCount'),
      pendingCount: n('pendingCount'),
    );
  }
}
