import 'admin_to_list_ui_models.dart';

/// 공고 카드 머리말이 말하는 수치 한 벌.
typedef GroupHeaderTotals = ({
  int confirmed,
  int pending,
  int required,
  int shortage,
  bool isFull,
});

/// [R7-5 §7] 카드 머리말 projection — **카드와 같은 함수**를 쓴다.
///
///   카드는 이 값을 `_updateGroupCache()` 에서 한 번 계산해 들고 있고,
///   같은 카드의 업무 행은 `resolveStats()` 를 매 build 에 다시 읽는다.
///   두 projection 의 갱신 시점이 다르면 한 화면에 `충원 1` 과 `충원 0` 이
///   같이 뜬다 — 사용자가 본 그 장면이다.
///
///   그래서 계산 자체를 한 곳에 두고 화면 없이 실행해 확인한다. 언제
///   다시 계산하는지(캐시 무효화)는 카드의 `didUpdateWidget` 이 정하고,
///   그쪽은 별도 계약이다.
///
/// [targetTOs] 가 비면 [singleFallback] 하나로 판정한다 — 장기·단건 카드가
/// 그 경로다. 같은 resolver 를 거치게 하려고 분기를 남겨 둔다.
GroupHeaderTotals projectGroupHeaderTotals({
  required List<TOItem> targetTOs,
  required TOItem Function() singleFallback,
}) {
  if (targetTOs.isEmpty) {
    final single = singleFallback();
    final s = single.resolveStats();
    return (
      confirmed: s.confirmed,
      pending: s.pending,
      required: s.required,
      shortage: s.shortage,
      isFull: single.resolvedIsFull,
    );
  }
  var c = 0, p = 0, r = 0, sh = 0;
  for (final t in targetTOs) {
    final s = t.resolveStats();
    c += s.confirmed;
    p += s.pending;
    r += s.required;
    sh += s.shortage;
  }
  return (
    confirmed: c,
    pending: p,
    required: r,
    shortage: sh,
    isFull: targetTOs.every((t) => t.resolvedIsFull),
  );
}
