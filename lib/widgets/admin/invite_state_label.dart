import 'package:flutter/material.dart';

import '../../models/core/application_model.dart';
import '../../models/ui/invite_capacity_state.dart';
import '../../theme/app_colors.dart';

/// [E2-INVITED-SEAT] 초대 행의 상태 문구 — 날짜별 명단과 업무별 창이 **같은 말**을 쓴다.
///
///   원래 `DayApplicantsDialog._inviteStateLabel` 이었다. 업무별 창은 초대 행을
///   아예 그리지 않아 같은 초대가 진입 경로에 따라 `초대 중 · 서류 확인 가능` 이기도,
///   `지원자가 없습니다` 이기도 했다. 식을 옮기기만 했다 — 문구·분기는 그대로다.
///
///   초대의 현재 의미는 canonical status + 기존 signal 에서 읽는다(새 enum 없음).
///   INVITED 는 capacity 를 함께 봐야 의미가 정해진다. 자리가 찼는데도 `초대 중`
///   이라고 하면 관리자는 오지 않을 응답을 기다린다.
(String, Color) inviteStateLabelOf(
  ApplicationModel app, {
  InviteCapacityState capacity = InviteCapacityState.unknown,
}) {
  switch (app.status) {
    case AppStatus.invited:
      // capacity 를 모르면 `초대 중`도 `모집 완료`도 사실이 아니다 — 모르는 것이다.
      switch (capacity) {
        case InviteCapacityState.available:
          // 근로자가 서류 열람에 동의해야 관리자가 확인할 수 있고,
          // 확인이 끝나야 근로자가 수락할 수 있다.
          return app.hasReviewPurposeConsent
              ? ('초대 중 · 서류 확인 가능', AppColors.infoDark)
              : ('초대 중 · 서류 동의 전', AppColors.infoDark);
        case InviteCapacityState.full:
          return ('모집 완료 · 정원 마감', AppColors.grey600);
        case InviteCapacityState.closed:
          // 자리가 남았을 수도 있다 — 더 이상 뽑지 않을 뿐이다.
          return ('모집 종료', AppColors.grey600);
        case InviteCapacityState.unknown:
          return ('상태 확인 불가', AppColors.grey500);
      }
    case AppStatus.confirmed:
    case AppStatus.contractPending:
      // invitedAt 이 있어 이 목록에 들어왔다 — 관리자 초대를 근로자가 수락했다.
      return ('초대 수락 · 확정', AppColors.successDark);
    case AppStatus.rejected:
      return ('초대 거절', AppColors.grey600);
    case AppStatus.canceled:
      // [INVITE-TERMINAL] 사업장 쪽 종료로 서버가 철회한 초대는 사유를 말한다.
      return (
        switch (app.cancelReason) {
          'RECRUIT_CLOSED' => '모집 마감으로 초대 종료',
          'BUSINESS_DEACTIVATED' => '사업장 비활성으로 종료',
          'TO_DELETED' => '공고 삭제로 종료',
          _ => '초대 철회',
        },
        AppColors.grey600,
      );
    case AppStatus.expired:
      return ('응답 만료', AppColors.grey600);
    case AppStatus.autoCanceled:
      return (
        switch (app.cancelReason) {
          'SCHEDULE_CONFLICT' => '일정 겹침 종료',
          'ACCOUNT_DELETED' => '탈퇴로 종료',
          _ => '자동 종료',
        },
        AppColors.grey600,
      );
    default:
      return (app.status, AppColors.grey600);
  }
}
