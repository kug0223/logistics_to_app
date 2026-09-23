// [CORRECTION-EXPIRED-UNDECIDED-RENEWAL-ACTION-SURFACE]
//
// 계약 연장/종료 **결정이 남아 있는가**를 한 곳에서만 판단한다.
//
//   Home 처리할 일 · 계약 종료 예정 화면 · 고정근무자 목록
//
// 셋이 각자 날짜 조건을 만들면 같은 사람을 두고 서로 다른 말을 한다.
// 실제로 그랬다 — Home 은 `workEndDate >= today` 로 조회했고, 만료 화면은
// `diff >= 0` 로 걸렀다. 둘 다 종료일이 지나는 순간 그 사람을 잊었다.
// 자동 연장이 그 순간 결정을 대신 내려 주던 동안에는 드러나지 않았다.
//
// 자동 연장을 걷어낸 뒤([AUTO-RENEW-POLICY]) 남은 사실은 이것이다:
//
//     근무 가능 여부  ≠  계약 결정 처리 여부
//
//     종료일 다음 날 → 근무 대상 아님 · 출근 대상 아님
//     그런데 renewalDecision 이 비어 있으면 **관리 업무는 아직 남아 있다.**
//
// 그래서 만료는 task 를 없애는 사건이 아니라 **더 급한 task** 로 만드는
// 사건이다.
//
// 저장하지 않는다. 기존 필드에서 파생한다 — isExpired / needsRenewal 같은
// 중복 상태를 Firestore 에 만들면 그것이 또 한 벌의 진실이 된다.

import '../models/core/application_model.dart';
import 'format_helper.dart';

/// 연장 결정이 남아 있는가.
enum RenewalDecisionState {
  /// 장기 근무관계가 아니거나, 기간을 말할 수 없다(workEndDate 없음).
  notApplicable,

  /// 종료가 다가온다 — 아직 결정하지 않았다.
  upcoming,

  /// **이미 종료됐는데** 아직 결정하지 않았다. 가장 급하다.
  expired,

  /// 연장·종료 결정이 끝났거나, 퇴사·해지로 관계가 정리됐다.
  resolved,
}

/// Home 이 "곧 종료"로 세는 창. 기존 D-15 알림과 같은 폭이다.
const int kRenewalUpcomingWindowDays = 15;

/// 이 지원서에 연장/종료 결정이 남아 있는가.
///
/// [today] 는 KST 달력 날짜여야 한다 — 호출자가 `FormatHelper.toKstDate`
/// 를 거친 값을 넘긴다. 로컬 시간대로 하루가 밀리면 D 와 D+1 의 의미가
/// 통째로 어긋난다.
RenewalDecisionState renewalDecisionStateOf(
  ApplicationModel app,
  DateTime today, {
  int upcomingWindowDays = kRenewalUpcomingWindowDays,
}) {
  if (!app.isLongTermApplication) return RenewalDecisionState.notApplicable;

  // 이미 결정했다. EXTEND 든 TERMINATE 든 더 물을 것이 없다.
  if (app.renewalDecision != null) return RenewalDecisionState.resolved;

  // 퇴사·해지가 확정된 관계는 연장 대상이 아니다.
  if (app.isTerminationApproved) return RenewalDecisionState.resolved;
  if (app.resignStatus == AppStatus.approved ||
      app.resignStatus == AppStatus.autoApproved) {
    return RenewalDecisionState.resolved;
  }
  if (app.terminationStatus == AppStatus.approved ||
      app.terminationStatus == AppStatus.autoApproved) {
    return RenewalDecisionState.resolved;
  }

  // 확정된 근무관계만 결정 대상이다. 지원·초대 단계는 다른 축이다.
  if (app.status != AppStatus.confirmed &&
      app.status != AppStatus.contractPending) {
    return RenewalDecisionState.notApplicable;
  }

  // 기간을 말할 수 없으면 종료도 말할 수 없다.
  final end = app.actualResignDate ?? app.workEndDate;
  if (end == null) return RenewalDecisionState.notApplicable;

  final endOnly = FormatHelper.toKstDate(end);
  final todayOnly = FormatHelper.toKstDate(today);
  final diff = endOnly.difference(todayOnly).inDays;

  // 종료일 D 는 마지막 근무 가능일이다 — 그 날까지는 "곧 종료"다.
  if (diff < 0) return RenewalDecisionState.expired;
  if (diff <= upcomingWindowDays) return RenewalDecisionState.upcoming;
  return RenewalDecisionState.notApplicable;
}

/// 결정이 남아 있는가 — Home·만료 화면·목록이 공유하는 하나의 질문.
bool needsRenewalDecision(ApplicationModel app, DateTime today) {
  final s = renewalDecisionStateOf(app, today);
  return s == RenewalDecisionState.upcoming || s == RenewalDecisionState.expired;
}

/// 지난 일수. 만료 건에서만 의미가 있다(양수 = 며칠 지났다).
int? renewalOverdueDays(ApplicationModel app, DateTime today) {
  if (renewalDecisionStateOf(app, today) != RenewalDecisionState.expired) {
    return null;
  }
  final end = app.actualResignDate ?? app.workEndDate;
  if (end == null) return null;
  return FormatHelper.toKstDate(today)
      .difference(FormatHelper.toKstDate(end))
      .inDays;
}

/// 만료가 먼저다. 같은 상태 안에서는 종료일이 이른 순.
///
/// 발견성 문제였다 — 만료된 건은 이미 늦었는데 목록 아래에 있으면
/// 더 늦어진다.
int compareRenewalUrgency(
  ApplicationModel a,
  ApplicationModel b,
  DateTime today,
) {
  int rank(ApplicationModel x) {
    switch (renewalDecisionStateOf(x, today)) {
      case RenewalDecisionState.expired:
        return 0;
      case RenewalDecisionState.upcoming:
        return 1;
      case RenewalDecisionState.resolved:
      case RenewalDecisionState.notApplicable:
        return 2;
    }
  }

  final r = rank(a).compareTo(rank(b));
  if (r != 0) return r;
  final ae = a.actualResignDate ?? a.workEndDate;
  final be = b.actualResignDate ?? b.workEndDate;
  if (ae == null || be == null) return 0;
  return FormatHelper.toKstDate(ae).compareTo(FormatHelper.toKstDate(be));
}
