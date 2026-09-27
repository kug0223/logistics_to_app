import '../models/core/application_model.dart';
import 'renewal_decision_state.dart';

/// [R7-P1-2 DEVICE.1E.1] 근무 관계를 **현재/이력**으로 가르는 한 곳.
///
///   DEVICE.1E 는 이 판정을 `occupiesSeatOn` 하나로 했다. 그것은 **좌석**
///   판정이지 **관계 종료** 판정이 아니다. 둘을 같은 것으로 쓰면 두 가지가
///   조용히 틀어진다.
///
///     만료 + 미결정   좌석은 비었지만 **결정이 남아 있다.** 이것을
///                     `계약 종료` 로 적으면 관리자의 할 일이 사라진다.
///                     (`renewal_decision_state.dart` 가 이미 그 축을 갖고 있다)
///
///     좌석 반납       NO_SHOW 대체충원(`staffingReleasedAt`)은 자리를
///                     내놓은 것이지 관계가 끝난 것이 아니다. 그런데
///                     `occupiesSeatOn` 은 이 필드를 보지 않으므로 현재
///                     인력으로 세어진다 — 정원 조회는 빼고 세는데.
///                     같은 다이얼로그에서 `확정 1` 과 `부족 2` 가 갈렸다.
///
///   새 정책도 새 enum 도 만들지 않는다. 이미 있는 세 canonical 사실
///   (`occupiesSeatOn` · `isStaffingReleased` · `renewalDecisionStateOf`)을
///   **한 곳에서** 조합할 뿐이다. 소비자마다 조건문을 다시 쓰면 세 번째
///   재발이 온다.
typedef StaffingRelation = ({
  /// 지금 이 자리를 채우는가 — 정원 집계와 **같은 규칙**이다.
  bool isCurrentStaffing,

  /// 자리를 반납했다(대체충원). 관계가 끝난 것은 아니다.
  bool seatReleased,

  /// 기간은 지났는데 연장/종료 결정이 남아 있다. 할 일이 있다.
  bool decisionPending,

  /// 결정이 끝났고 기간도 지났다. 이력이다.
  bool resolvedEnded,

  /// 종료가 예정돼 있고 아직 그 날이 오지 않았다.
  bool endingSoon,
});

/// [now] 는 판정 기준 시각. 날짜 비교는 내부에서 KST 달력으로 정규화한다.
StaffingRelation staffingRelationOf(ApplicationModel app, DateTime now) {
  final occupies = app.occupiesSeatOn(now);
  final released = app.isStaffingReleased;

  if (!occupies) {
    // 좌석이 비었다. 그 다음 질문은 **결정이 끝났는가** 다.
    final decision = renewalDecisionStateOf(app, now);
    final pending = decision == RenewalDecisionState.expired;
    return (
      isCurrentStaffing: false,
      seatReleased: released,
      decisionPending: pending,
      // 만료+미결정을 종료로 적지 않는다. 결정이 끝났을 때만 이력이다.
      resolvedEnded: !pending,
      endingSoon: false,
    );
  }

  // 좌석은 살아 있다 — 즉 종료일이 없거나 아직 D 가 지나지 않았다.
  //   D 당일도 아직 근무일이므로 `예정` 이다(고정근무 관리와 같은 기준).
  final ending =
      app.isLongTermApplication && app.effectiveEndDate != null;
  return (
    // 반납한 자리는 현재 인력으로 세지 않는다 — 정원 조회와 같다.
    isCurrentStaffing: !released,
    seatReleased: released,
    decisionPending: false,
    resolvedEnded: false,
    endingSoon: ending,
  );
}

/// 이 관계의 primary 라벨. **기존 어휘만** 쓴다.
///
///   `계약 종료 예정` / `계약 종료` 는 고정근무 관리가 쓰는 말이고,
///   `계약 확인 필요` 는 만료+미결정에 대해 Home·만료 화면이 쓰는 말이다.
///   현재 유효한 관계에는 별도 lifecycle 라벨을 붙이지 않는다(null).
String? staffingRelationLabel(ApplicationModel app, DateTime now) {
  final r = staffingRelationOf(app, now);
  if (r.decisionPending) return '계약 확인 필요';
  if (r.resolvedEnded) return '계약 종료';
  if (r.seatReleased) return '좌석 반납';
  if (r.endingSoon) return '계약 종료 예정';
  return null;
}
