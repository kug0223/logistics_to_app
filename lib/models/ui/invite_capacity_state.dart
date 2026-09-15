// [SYSTEM-INTEGRATION-R2.2.1 CORRECTION] 초대가 지금 수락될 수 있는가 — 세 상태.
//
// 원래 이 판정은 `bool?`이었다. 그래서 호출부가 `!= true`라고 쓸 수 있었고,
// Dart에서 `null != true`는 true이므로 **UNKNOWN이 조용히 `자리 있음`으로**
// 흘러들었다. 인력 현황을 읽지 못한 상태에서 `초대 중 2명`과
// `인력 초대 (3명 부족)`을 띄우는 경로였다 — 확인하지 못한 것을 확인한 것처럼
// 말하는 것이다.
//
//   UNKNOWN != AVAILABLE     UNKNOWN != FULL     ERROR != ZERO
//
// enum으로 두면 세 갈래를 각각 쓰지 않고는 분기할 수 없다. `!= true` 한 줄로
// 두 상태를 뭉뚱그리는 실수가 타입 차원에서 불가능해진다.

enum InviteCapacityState {
  /// canonical capacity를 읽었고 자리가 남았다 — 초대가 수락될 수 있다.
  available,

  /// 자리가 **다 찼다**. 필요한 만큼 사람을 구했다는 뜻이다.
  full,

  /// 모집이 **종료됐다**. 자리가 남아 있어도 더 이상 뽑지 않는다.
  ///
  /// [R2 FINAL SEMANTIC CORRECTION] full과 합치지 않는다.
  ///
  ///   `필요 5 · 확정 2 · 관리자가 마감`
  ///     full이라고 부르면 → "이 근무는 인원이 모두 찼어요" (거짓)
  ///     closed라고 부르면 → "모집이 종료됐어요"            (사실)
  ///
  ///   수락할 수 없다는 **결과**는 같지만 말해 주는 **이유**가 다르다.
  ///   근로자는 왜 자기 초대가 무효가 됐는지 알 권리가 있고, 관리자는
  ///   자기가 마감한 것과 사람이 다 찬 것을 구분할 수 있어야 한다.
  closed,

  /// canonical capacity를 읽지 못했다 — 수락 가능한지도, 찼는지도, 종료됐는지도
  /// 말할 수 없다.
  unknown,
}

/// 근로자 화면의 `workInstanceFull`과 **같은 식**을 쓴다.
///
///   서버 `callableGetMyApplications`:
///     `req > 0 && workDetailCounts[wdId].confirmedCount >= req`
///
/// 관리자가 다른 식을 쓰면 한쪽은 `수락 불가`, 다른 쪽은 `초대 중`이 된다.
///
/// [canonicalConfirmed]는 slot이 준 값이어야 한다 — 지원서에서 세지 않는다.
/// null이면 그 모집 단위의 canonical row가 없다는 뜻이고, 그때는 FULL로도
/// CLOSED로도 여유로도 단정하지 않는다.
///
/// [isClosed]는 읽어서 안 사실일 때만 true다. 정원보다 **먼저** 본다 —
/// 종료된 모집은 자리가 남아 있어도 종료다.
InviteCapacityState inviteCapacityStateOf({
  required int? canonicalConfirmed,
  required int requiredCount,
  bool isClosed = false,
}) {
  if (canonicalConfirmed == null) return InviteCapacityState.unknown;
  if (isClosed) return InviteCapacityState.closed;
  if (requiredCount > 0 && canonicalConfirmed >= requiredCount) {
    return InviteCapacityState.full;
  }
  return InviteCapacityState.available;
}
