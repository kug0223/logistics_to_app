import 'admin_to_list_ui_models.dart';

/// 공고 카드 머리말이 말하는 수치 한 벌.
typedef GroupHeaderTotals = ({
  int confirmed,
  int pending,
  int required,
  int shortage,
  bool isFull,

  /// [COLLAPSED-EXPANDED] 정원을 **말할 수 있는가**.
  ///
  ///   false 면 `필요 미설정` 이 아니라 `모름` 이다. 업무 정의도 없고
  ///   카운터도 0 이면 우리는 정원을 모르는 것이고, 그것을 `미설정` 으로
  ///   적으면 조회 실패가 운영 사실로 둔갑한다(ERROR != ZERO).
  bool requiredKnown,
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
///
/// [ADMIN-APPROVAL-MIXED-SLOTS] [openShortageOf] 가 주어지면 슬롯마다 그 값(마감된
///   업무·슬롯을 뺀 부족)을 더한다. `부족`은 "지금 처리 가능한 미완료"다 — 날짜 창(`_GroupData.shortage`
///   = `staffingShortageOf`, closed → 0)과 같은 뜻이다. 열린 슬롯과 마감 슬롯이
///   섞인 공고에서 카드는 `부족 5`(0/3 마감 + 0/2 열림)인데 날짜 창은 날짜별로
///   0·2 라 합이 2였다. 충원·필요·대기는 사실이라 그대로 더한다.
///   [CLOSESTATE-BOUNDARY] 마감 판정은 **저장 상태**(TOItem.persistedOpenShortage)
///   — 날짜 창·서버 초대와 같은 원천이다. 기기 시계 판정을 쓰지 않는다.
GroupHeaderTotals projectGroupHeaderTotals({
  required List<TOItem> targetTOs,
  required TOItem Function() singleFallback,
  int Function(TOItem t)? openShortageOf,
}) {
  if (targetTOs.isEmpty) {
    final single = singleFallback();
    final s = single.resolveStats();
    return (
      confirmed: s.confirmed,
      pending: s.pending,
      required: s.required,
      shortage: openShortageOf?.call(single) ?? s.shortage,
      isFull: single.resolvedIsFull,
      requiredKnown: single.isRequiredKnown,
    );
  }
  var c = 0, p = 0, r = 0, sh = 0;
  // 하나라도 정원을 모르면 합계도 모르는 것이다 — 아는 것만 더해
  //   `필요 N` 이라고 말하면 그 N 이 전체인 줄로 읽힌다.
  var known = true;
  for (final t in targetTOs) {
    final s = t.resolveStats();
    c += s.confirmed;
    p += s.pending;
    r += s.required;
    sh += openShortageOf?.call(t) ?? s.shortage;
    if (!t.isRequiredKnown) known = false;
  }
  return (
    confirmed: c,
    pending: p,
    required: r,
    shortage: sh,
    isFull: targetTOs.every((t) => t.resolvedIsFull),
    requiredKnown: known,
  );
}
