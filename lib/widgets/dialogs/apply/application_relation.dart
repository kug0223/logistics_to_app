// lib/widgets/dialogs/apply/application_relation.dart
//
// [R7-P4.4E.7A] 근로자와 **한 근무** 사이의 지원 관계 — 판정의 단일 소유자.
//
// 왜 한 곳으로 모으는가
//   같은 관계를 세 곳이 서로 다른 키로 보고 있었다.
//     서버 `srvFindRelationApplications` : (uid, toId, slotId, **wdId**)
//     `MultiApplyConfirmSheet`           : (toId, slotId, **workType**)
//     `ApplyWorkDialog`                  : (date, **workType_start_end**)
//   그리고 공고 상세(`job_posting_screen`)는 **아예 보지 않았다** — 이미 지원한
//   업무에도 `선택` 을 그리고 그걸 CTA 수치에 셌다.
//
//   workType 단독 매칭은 서버가 주석으로 경고한 실수다:
//   "같은 업무명(workType)만 보고 합치면 시간대가 다른 별개 근무가 하나로
//    뭉쳐 **정상 지원이 막힌다**" (`srvFindRelationApplications`).
//   실제로 같은 업무명이 시간대만 다른 두 근무가 있으면, 하나에 지원한 뒤
//   다른 하나를 고르면 제출에서 조용히 빠졌다.
//
// 새 identity 를 만들지 않는다
//   `WorkDetailData.canonicalId`(= `wdId ?? workType_start_end`)가 이미 있고
//   "새 identity 개념을 만들지 않는다" 고 그 주석이 적어 뒀다. 여기서도
//   **wdId 우선 · 레거시만 workType+시작+종료 폴백** 을 쓴다.
//
// 상태 그룹도 만들지 않는다
//   `AppStatus.activeStates` / `inviteStates` / `inactiveStates` 를 그대로 쓴다.
import '../../../models/core/application_model.dart';
import '../../../models/core/work_detail_data.dart';

/// 한 근무에 대한 현재 관계. `none` 이면 신규 지원 후보다.
enum WorkApplyRelation {
  /// 관계 없음 — 신규 지원 가능.
  none,

  /// 근로자가 지원해 관리자 응답을 기다린다. (PENDING)
  pending,

  /// 관리자가 초대했고 근로자가 아직 답하지 않았다. (INVITED)
  ///
  /// 서버는 이 상태에 **다시 지원하는 것을 막고** 다른 문구를 준다 —
  /// "이미 초대를 받은 근무입니다. 내 지원 내역에서 초대를 확인해주세요."
  /// 초대는 수락·거절로 답하는 것이지 다시 지원하는 것이 아니다.
  invited,

  /// 확정 후 쌍방 서명 대기. (CONTRACT_PENDING)
  contractPending,

  /// 계약 체결 완료. (CONFIRMED)
  confirmed,
}

extension WorkApplyRelationX on WorkApplyRelation {
  /// 신규 지원을 막는 관계인가. `none` 만 아니면 전부 막는다.
  bool get blocksNewApplication => this != WorkApplyRelation.none;

  /// 초대에 답해야 하는 상태인가 — 지원 affordance 를 주면 안 된다.
  bool get isInvitation => this == WorkApplyRelation.invited;
}

/// 관계 판정 — 공고 상세와 확인 시트가 **같은 판정**을 소비한다.
class ApplicationRelationResolver {
  const ApplicationRelationResolver._();

  /// [myApplications] 안에서 (`toId`, `slotId`, [work]) 에 해당하는 관계를 찾는다.
  ///
  /// 비활성 지원서(REJECTED·CANCELED·AUTO_CANCELED)와 EXPIRED 는 **관계로
  /// 돌려주지 않는다** — 서버가 재지원을 허용하는 상태들이다.
  /// 퇴사·해지 결정이 내려진 약속도 관계로 보지 않는다(서버도 guard 를 건너뛴다).
  static WorkApplyRelation resolve({
    required List<ApplicationModel> myApplications,
    required String toId,
    required String? slotId,
    required WorkDetailData work,
  }) =>
      match(
        myApplications: myApplications,
        toId: toId,
        slotId: slotId,
        work: work,
      ).relation;

  /// 관계와 **그 관계를 만든 지원서**를 함께 돌려준다.
  ///
  /// 취소·확정취소처럼 그 문서를 직접 다루는 화면이 있어서 둘을 같이 준다.
  /// 판정과 대상을 서로 다른 코드가 고르면 또 갈라진다 — 한 곳이 말한다.
  static ({WorkApplyRelation relation, ApplicationModel? application}) match({
    required List<ApplicationModel> myApplications,
    required String toId,
    required String? slotId,
    required WorkDetailData work,
  }) {
    WorkApplyRelation found = WorkApplyRelation.none;
    ApplicationModel? hit;
    for (final app in myApplications) {
      if (!_sameWork(app: app, toId: toId, slotId: slotId, work: work)) {
        continue;
      }
      final r = _relationOf(app);
      if (r == WorkApplyRelation.none) continue;
      // 여러 줄이 잡히면 더 강한 약속을 보여준다.
      if (_rank(r) > _rank(found)) {
        found = r;
        hit = app;
      }
    }
    return (relation: found, application: hit);
  }

  /// 같은 근무인가. **wdId 우선, 레거시만 폴백.** workType 단독 비교는 하지 않는다.
  static bool _sameWork({
    required ApplicationModel app,
    required String toId,
    required String? slotId,
    required WorkDetailData work,
  }) {
    if (app.toId != toId) return false;

    // slotId 가 없으면 contract TO — slotId 없는 지원서와 맞춘다.
    final sameSlot = (slotId == null || slotId.isEmpty)
        ? (app.slotId == null || app.slotId!.isEmpty)
        : app.slotId == slotId;
    if (!sameSlot) return false;

    final workWdId = work.wdId;
    final appWdId = app.wdId;
    final bothHaveWdId = workWdId != null &&
        workWdId.isNotEmpty &&
        appWdId != null &&
        appWdId.isNotEmpty;

    if (bothHaveWdId) return appWdId == workWdId;

    // 레거시 — wdId 가 한쪽이라도 없다. 업무명만으로는 시간대가 다른 별개
    // 근무를 하나로 뭉치므로 **시작·종료까지** 같아야 한다.
    return app.selectedWorkType == work.workType &&
        app.startTime == work.startTime &&
        app.endTime == work.endTime;
  }

  /// 지원서 상태 → 관계. canonical 상태 그룹을 그대로 쓴다.
  static WorkApplyRelation _relationOf(ApplicationModel app) {
    // 퇴사·해지 결정이 내려진 약속은 끝난 관계다 — 서버도 중복 guard 를
    // 건너뛰고 재지원을 허용한다.
    if (app.isExitDecided) return WorkApplyRelation.none;

    final s = app.status;
    if (s == AppStatus.confirmed) return WorkApplyRelation.confirmed;
    if (s == AppStatus.contractPending) return WorkApplyRelation.contractPending;
    if (s == AppStatus.pending) return WorkApplyRelation.pending;
    if (s == AppStatus.invited) return WorkApplyRelation.invited;

    // REJECTED · CANCELED · AUTO_CANCELED · EXPIRED — 재지원 가능.
    //   EXPIRED 는 서버의 active/inactive 어느 집합에도 없어 신규 지원으로
    //   통과한다. 여기서도 관계로 보지 않는다(서버 계약을 그대로 비춘다).
    return WorkApplyRelation.none;
  }

  static int _rank(WorkApplyRelation r) => switch (r) {
        WorkApplyRelation.none => 0,
        WorkApplyRelation.invited => 1,
        WorkApplyRelation.pending => 2,
        WorkApplyRelation.contractPending => 3,
        WorkApplyRelation.confirmed => 4,
      };
}
