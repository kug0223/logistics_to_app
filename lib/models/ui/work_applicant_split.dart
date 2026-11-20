import '../core/application_model.dart';

/// [E2-INVITED-SEAT] 업무별 지원자 창이 **한 번 받은 응답**을 두 목록으로 나눈다.
///
///   active  — 직접 지원·확정 계열(PENDING / CONTRACT_PENDING / CONFIRMED).
///             승인·거절·계약 같은 기존 행동의 대상이다.
///   invites — 아직 응답하지 않은 초대(INVITED). 승인 버튼을 붙이지 않는다.
///
///   예전에는 active 만 남기고 INVITED 를 버려서, 초대만 있는 업무를 열면
///   `지원자가 없습니다` 였다(원장 pendingCount 1, 날짜별 명단 `초대 중`).
///   끝난 초대(EXPIRED·REJECTED·CANCELED·AUTO_CANCELED)는 어느 쪽에도 넣지
///   않는다 — 이 창은 현재 인력 화면이고, 끝난 초대의 이력은 날짜별 명단이 말한다.
///
///   [belongs] 는 이 창의 업무 소속 판정(wdId 우선 → legacy)이다. 두 목록이
///   **같은 판정**을 쓴다.
({List<ApplicationModel> active, List<ApplicationModel> invites})
    splitWorkApplications(
  Iterable<ApplicationModel> apps,
  bool Function(ApplicationModel app) belongs,
) {
  const activeStatuses = {
    AppStatus.pending,
    AppStatus.contractPending,
    AppStatus.confirmed,
  };
  final active = <ApplicationModel>[];
  final invites = <ApplicationModel>[];
  for (final app in apps) {
    if (!belongs(app)) continue;
    if (activeStatuses.contains(app.status)) {
      active.add(app);
    } else if (app.status == AppStatus.invited) {
      invites.add(app);
    }
  }
  invites.sort(
      (a, b) => (a.invitedAt ?? a.appliedAt).compareTo(b.invitedAt ?? b.appliedAt));
  return (active: active, invites: invites);
}
