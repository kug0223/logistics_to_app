import '../core/work_detail_data.dart';

/// [R7-4 C3~C7] 한 업무 정의의 정원 판독 — **"모른다"와 "0"을 구분하는 창구**.
///
/// 이 클래스가 새로 만드는 상태는 없다. 이미 있는 두 계약을 그대로 쓴다:
///   - identity: [WorkDetailData.lookupByIdentity] (canonicalId → composite 순)
///   - 실패 표시: 호출부가 이미 들고 있는 `workDetailStatsFailed`
///
/// 있는 것은 판단 규칙 하나뿐이다 — **조회가 빗나가면 0이 아니라 UNKNOWN 이다.**
///
/// 서버는 같은 상황을 이미 이렇게 다룬다. `getWorkDetailCount` 는 wdId 는
/// 있는데 카운터 항목이 없으면 `failed-precondition` 으로 막고, 주석에
/// 이유를 적어 두었다 — *"fail-open(0/0)은 '정원 여유 있음'으로 오판 →
/// 정원 초과 지원 허용하는 보안 버그."*
///
/// 클라이언트에서 같은 miss 를 `?? 0` 으로 접으면 화면은 반대로 말한다.
/// 자리가 다 찼는데 `잔여 5명`이라고 적고, 정원이 찬 업무에 승인 버튼을 연다.
/// 서버가 최종적으로 막아주더라도, 그때까지 관리자와 지원자는 틀린 것을 보고
/// 움직인 것이다. 그래서 표시와 판단을 같은 판독기 하나에서 낸다.
class WorkCapacityReading {
  const WorkCapacityReading._({
    required this.isKnown,
    required this.requiredCount,
    int? confirmed,
    int? pending,
  })  : _confirmed = confirmed,
        _pending = pending;

  /// 이 업무의 정원 수치를 **실제로 안다**. false 면 숫자를 말하지 않는다.
  final bool isKnown;

  /// 필요 인원. 이것은 업무 정의 자체에서 오므로 통계 실패와 무관하게 안다.
  final int requiredCount;

  final int? _confirmed;
  final int? _pending;

  /// 모른다고 판정한 경우 — 통계 실패, 미로드, 또는 **identity miss**.
  static WorkCapacityReading unknown(int requiredCount) =>
      WorkCapacityReading._(isKnown: false, requiredCount: requiredCount);

  /// 확정 인원. 모를 때는 null — 0 으로 접지 않는다.
  int? get confirmed => isKnown ? (_confirmed ?? 0) : null;

  /// 대기 인원. 모를 때는 null.
  int? get pending => isKnown ? (_pending ?? 0) : null;

  /// 남은 자리. 모를 때는 null — `잔여 N명`을 말할 수 없다는 뜻이다.
  int? get remaining {
    final c = confirmed;
    if (c == null) return null;
    final r = requiredCount - c;
    return r > 0 ? r : 0;
  }

  /// 정원이 찼다고 **단정**할 수 있는가. 모르면 false — 모른다고 마감이라 하지 않는다.
  bool get isFull =>
      isKnown && requiredCount > 0 && (confirmed ?? 0) >= requiredCount;

  /// [n]명을 추가로 확정해도 정원 안인가.
  ///
  /// 모를 때는 **null** 이다. 호출부가 `?? true` 로 접으면 fail-open 이고
  /// `?? false` 로 접으면 아는 것도 없이 막는 것이다 — 둘 다 하지 말라고
  /// null 을 돌려준다. 모르면 "지금은 판단할 수 없다"고 말해야 한다.
  bool? canAdmit(int n) {
    if (!isKnown) return null;
    if (requiredCount <= 0) return true;
    return (confirmed ?? 0) + n <= requiredCount;
  }

  /// [R7-4] 이 업무의 정원을 읽는다.
  ///
  /// [statsFailed] 는 조회 자체가 실패했다는 호출부의 사실이고,
  /// map 이 null 이거나 이 업무가 map 에 없으면(=identity miss) 역시 모른다.
  /// **map 이 있다는 사실만으로 안다고 판정하지 않는다** — 그게 C4 였다.
  static WorkCapacityReading read(
    WorkDetailData work,
    Map<String, Map<String, int>>? stats, {
    bool statsFailed = false,
  }) {
    if (statsFailed) return unknown(work.requiredCount);
    final s = work.lookupByIdentity(stats);
    if (s == null) return unknown(work.requiredCount);
    return WorkCapacityReading._(
      isKnown: true,
      requiredCount: work.requiredCount,
      confirmed: s['confirmed'],
      pending: s['pending'],
    );
  }
}

/// [R7-4 C5·C6] 승인 전 정원 관문의 판정 본체.
///
/// 막을 이유가 있으면 그 문구를, 없으면 null 을 돌려준다.
/// 단건 승인과 일괄 승인이 같은 함수를 쓴다 — 두 자리가 각자 계산하던 때에
/// 한쪽만 고쳐지는 일이 반복됐다.
///
/// [confirmed] 가 null 이면 **모른다**는 뜻이다. 0 으로 접지 않는다.
/// 이 판정은 최종 권위가 아니다 — 마지막 한 자리를 두고 겹치는 경우는
/// 서버 transaction 이 막는다. 여기서는 서버가 거절할 것을 미리 알릴 뿐이다.
String? capacityBlockReason({
  required int? confirmed,
  required int requiredCount,
  required int addCount,
}) {
  if (confirmed == null) {
    return '정원을 확인하지 못했습니다. 목록을 새로고침한 뒤 다시 시도해주세요.';
  }
  final remaining = requiredCount - confirmed;
  if (remaining <= 0) {
    return '필요 인원($requiredCount명)이 이미 충족되었습니다.';
  }
  if (addCount > remaining) {
    return '필요 인원($requiredCount명)을 초과합니다. '
        '현재 $confirmed명 확정, $remaining명 추가 가능';
  }
  return null;
}
