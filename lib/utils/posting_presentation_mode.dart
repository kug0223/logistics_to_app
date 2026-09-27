import 'format_helper.dart';

/// [R7-P1-2 DEVICE.1D] 공고 카드가 "무엇을 묻는 화면인가"를 한 곳에서 정한다.
///
///   현재-좌석 의미를 제대로 적용하면, 운영이 끝난 장기공고는 자연스럽게
///   `충원 0 / 필요 2 · 부족 2` 가 된다. 산술은 맞다. 그런데 읽는 사람에게는
///   **"결국 아무도 못 구했고 지금도 2명이 부족하다"** 로 읽힌다.
///
///   끝난 공고가 묻는 질문은 다르다.
///
///     운영 중  → 지금 몇 자리가 비었고 무엇을 해야 하는가
///     운영 종료 → 무슨 일이 있었는가
///
///   그래서 같은 숫자를 같은 자리에 계속 두지 않는다.
///
///   ── 두 축을 섞지 않는다 ───────────────────────────────────────
///
///   모집 마감(`recruitmentClosed`)과 운영 종료(`operationEnd`)는 다른 사실이다.
///   지원은 9/20 에 닫혔어도 근무는 10/23 까지 이어질 수 있다. 그 공고는
///   `마감됨` 탭에 있지만 운영은 살아 있다 — CLOSED_ACTIVE 다.
///
///   ── 근로자 한 명의 종료로 공고를 끝내지 않는다 ────────────────
///
///   9/22 에 계약이 끝난 사람이 있어도 공고의 운영 기간이 10/23 까지면
///   그 공고는 ACTIVE 다. 오히려 그때가 사람을 더 구해야 하는 순간이다.
enum PostingPresentationMode {
  /// 운영 기간이 남아 있고 모집도 열려 있다.
  active,

  /// 모집은 닫혔지만 근무는 아직 남아 있다.
  closedActive,

  /// 공고의 운영 기간 자체가 끝났다.
  pastEnded,
}

/// 공고 카드·업무 상세가 함께 쓰는 단일 판정.
///
/// [operationEnd] 이 공고의 마지막 근무 가능일(장기: rangeEnd, 단기: 마지막 슬롯일).
///   모르면 null — 그때는 끝났다고 단정하지 않는다.
/// [recruitmentClosed] 모집 lifecycle 이 닫혔는가(탭 술어와 같은 값).
/// [now] 테스트 주입용. 기본값은 지금.
///
/// 날짜는 KST 달력으로만 본다 — 기기 timezone 으로 공고의 생사를 정하지 않는다.
PostingPresentationMode resolvePostingPresentationMode({
  required DateTime? operationEnd,
  required bool recruitmentClosed,
  DateTime? now,
}) {
  if (operationEnd != null) {
    final today = FormatHelper.toKstDate(now ?? DateTime.now());
    final end = FormatHelper.toKstDate(operationEnd);
    // 마지막 근무일 당일은 아직 운영 중이다. 그 다음 날부터 끝난 것이다.
    if (end.isBefore(today)) return PostingPresentationMode.pastEnded;
  }
  return recruitmentClosed
      ? PostingPresentationMode.closedActive
      : PostingPresentationMode.active;
}

extension PostingPresentationModeX on PostingPresentationMode {
  /// 현재 운영을 위한 수치(충원·부족·미충원·N/M)를 대표 정보로 쓰는가.
  ///
  ///   끝난 공고에서는 쓰지 않는다. 숫자를 지우는 것이 아니라 **대표 자리에서
  ///   내리는 것**이다 — 원래 필요 인원과 사람 이력은 그대로 남는다.
  bool get showsCurrentStaffing => this != PostingPresentationMode.pastEnded;

  /// 끝난 공고의 대표 문구.
  bool get isTerminal => this == PostingPresentationMode.pastEnded;
}
