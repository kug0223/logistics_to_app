// lib/models/ui/invitation_projection.dart
//
// [CROSS-DOMAIN-R5.3D] 통합 초대 상세의 view model.
//
// 초대 상세는 "공고를 다시 보는 화면"이 아니라
// **"내가 받은 제안의 내용을 보고 수락하는 화면"** 이다.
// 그래서 화면에 오는 값을 세 층으로 나눈다:
//
//   PROMISE       내가 수락하면 적용될 조건 — Application 스냅샷에서만 온다.
//   CONTEXT       근무 안내 — 공고·사업장의 **현재** 정보. 설명일 뿐이다.
//   ACCEPTABILITY 지금 수락할 수 있는가 — 서버가 준 fresh 상태로 판정한다.
//
// 이 분리가 무너지면 "현재 공고 급여"가 수락 조건처럼 보인다.
// 공고는 초대 이후에도 바뀔 수 있고, 바뀌어도 약속은 그대로다.

import '../core/application_model.dart';
import '../core/work_detail_model.dart';
import 'invite_capacity_state.dart';

/// 지금 이 초대를 수락할 수 있는가 — 그리고 못 한다면 왜인가.
enum InvitationAcceptability {
  /// 수락할 수 있다.
  acceptable,

  /// 이 근무에 자리가 다 찼다.
  full,

  /// 모집이 종료됐다(자리가 남아 있어도).
  closed,

  /// 수락 가능한지 **판단하지 못했다**. 찼다고도 비었다고도 말하지 않는다.
  unknown,

  /// 이 Application이 더 이상 INVITED가 아니다 — 이미 답했거나 만료됐다.
  alreadyResolved,
}

/// 공고 context를 지금 읽을 수 있는가.
enum InvitationContextState {
  /// 공고를 읽었다.
  loaded,

  /// 공고를 읽지 못했다(네트워크·권한·삭제). **초대가 없다는 뜻이 아니다.**
  unavailable,
}

/// [R5.3D] 약속과 현재 공고가 실제로 다른 항목.
///
/// 숫자를 두 줄로 나열하기 위한 것이 아니다 — 안내 문구를 띄울지
/// 결정하기 위한 advisory 용도다.
class InvitationDrift {
  final bool wage;
  final bool wageType;
  final bool time;
  final bool breakMinutes;
  final bool workType;

  const InvitationDrift({
    this.wage = false,
    this.wageType = false,
    this.time = false,
    this.breakMinutes = false,
    this.workType = false,
  });

  bool get hasAny => wage || wageType || time || breakMinutes || workType;
}

/// 통합 초대 상세가 읽는 단 하나의 view model.
class InvitationProjection {
  /// PROMISE — 수락하면 적용될 조건. 언제나 Application에서 온다.
  final ApplicationModel application;

  /// CONTEXT — 공고를 읽었는가.
  final InvitationContextState contextState;

  /// ACCEPTABILITY — 지금 수락할 수 있는가.
  final InvitationAcceptability acceptability;

  /// 약속과 현재 공고의 차이(있을 때만 안내한다).
  final InvitationDrift drift;

  const InvitationProjection({
    required this.application,
    required this.contextState,
    required this.acceptability,
    required this.drift,
  });

  /// 이 초대가 '다른 업무 제안'인가 — 기존 지원(A)이 살아 있다는 뜻이다.
  bool get isAlternativeOffer => application.isAlternativeWorkOffer;

  /// 이 급여가 이 사람에게만 적용되는 개별 조건인가.
  bool get hasIndividualCompensation => application.hasIndividualCompensation;

  bool get canAccept => acceptability == InvitationAcceptability.acceptable;

  /// 수락할 수 없는 이유 — 없으면 null.
  ///
  /// 이유를 말하지 못하는 상태(unknown)를 "찼다"로 바꾸지 않는다.
  String? get blockedReason {
    switch (acceptability) {
      case InvitationAcceptability.acceptable:
        return null;
      case InvitationAcceptability.full:
        return '현재 이 업무는 인원이 모두 차서 수락할 수 없습니다.';
      case InvitationAcceptability.closed:
        return '현재 이 업무는 모집이 종료되어 수락할 수 없습니다.';
      case InvitationAcceptability.unknown:
        return '지금 수락 가능한지 확인하지 못했어요. 새로고침 후 다시 시도해주세요.';
      case InvitationAcceptability.alreadyResolved:
        return '이미 처리된 초대입니다.';
    }
  }

  /// [R5.3D] 약속과 현재 공고가 다를 때의 **안내 한 줄**.
  ///
  /// 현재 금액을 경쟁하는 진실로 나란히 놓지 않는다 — 무엇이 적용되는지만
  /// 말한다. 실제 차이가 있을 때만 나온다.
  String? get driftNotice => drift.hasAny
      ? '공고 내용이 초대 이후 변경되었습니다.\n수락 시 위에 표시된 초대 조건이 적용됩니다.'
      : null;

  /// 세 층을 조립한다. **여기가 유일한 판정 지점이다.**
  ///
  /// [liveWorkDetail]은 공고의 현재 값이고, 없으면(삭제·미로딩) drift를
  /// 계산하지 않는다 — 읽지 못한 것을 "달라졌다"고 말하지 않는다.
  factory InvitationProjection.of({
    required ApplicationModel application,
    required bool postingLoaded,
    WorkDetailModel? liveWorkDetail,
  }) {
    final resolved = application.status != 'INVITED';
    final acceptability = resolved
        ? InvitationAcceptability.alreadyResolved
        : switch (application.workInstanceCapacityState) {
            InviteCapacityState.available => InvitationAcceptability.acceptable,
            InviteCapacityState.full => InvitationAcceptability.full,
            InviteCapacityState.closed => InvitationAcceptability.closed,
            InviteCapacityState.unknown => InvitationAcceptability.unknown,
          };

    return InvitationProjection(
      application: application,
      contextState: postingLoaded
          ? InvitationContextState.loaded
          : InvitationContextState.unavailable,
      acceptability: acceptability,
      drift: _driftOf(application, liveWorkDetail),
    );
  }

  static InvitationDrift _driftOf(ApplicationModel app, WorkDetailModel? live) {
    if (live == null) return const InvitationDrift();
    return InvitationDrift(
      wage: live.wage != app.wage,
      wageType: app.wageType != null && live.wageType != app.wageType,
      time: live.startTime != app.startTime || live.endTime != app.endTime,
      // 약속에 휴게가 없으면(레거시) 비교하지 않는다 — 모르는 것을 다르다고
      // 말하지 않는다.
      breakMinutes:
          app.breakMinutes != null && live.breakMinutes != app.breakMinutes,
      workType: live.workType != app.selectedWorkType,
    );
  }
}
