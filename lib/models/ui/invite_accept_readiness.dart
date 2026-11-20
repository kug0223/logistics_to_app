// [INVITE-PREACCEPT] 초대를 지금 **수락할 수 있는가** — 근로자 쪽 상태.
//
// 판정은 서버가 한다(`srvInviteAcceptReadiness` → 사업장별 신분증 확인).
// 화면이 다시 계산하지 않는다 — 수락 callable 과 같은 함수가 내려준 값을
// 그대로 쓴다. 따로 계산하면 `수락하기`를 띄웠는데 서버가 거절하는 일이
// 다시 생긴다(2026-10-15 DEV 실측: 자동 판정이 MATCHED 가 아닌 근로자는
// 관리자가 검토할 방법이 없어 초대를 수락할 수 없었다).
//
//   UNKNOWN != READY — 못 읽은 것은 수락할 수 있다는 뜻이 아니다. 다만
//   수락 버튼을 막지는 않는다: 최종 판정은 서버가 다시 하고, 막아 두면
//   서버가 허용할 수락을 화면이 막는 일이 생긴다.

enum InviteAcceptReadiness {
  /// 사업장 검토 또는 자동 판정이 끝났다 — 수락할 수 있다.
  ready,

  /// 신분증이 등록되어 있지 않다 — 등록부터 해야 한다.
  documentRequired,

  /// 이 초대에 서류 열람 동의가 없다 — 동의해야 사업장이 확인할 수 있다.
  consentRequired,

  /// 동의했다 — 사업장 확인을 기다린다.
  reviewPending,

  /// 서버가 **조회에 실패했다고 알려 왔다**(UNAVAILABLE). 다시 확인할 수 있다.
  ///
  /// [unknown] 과 다르다: unknown 은 값이 아예 없는 것(구버전 서버·초대 아님)이고,
  /// 이것은 서버가 확인하려다 못 한 것이다. 둘 다 READY 가 아니다.
  unavailable,

  /// 서버가 값을 주지 않았다(구버전 서버·초대 아님).
  unknown,
}

/// 서버 문자열 → 상태. 모르는 값은 전부 unknown 이다.
InviteAcceptReadiness parseInviteAcceptReadiness(Object? raw) {
  switch (raw) {
    case 'READY':
      return InviteAcceptReadiness.ready;
    case 'DOCUMENT_REQUIRED':
      return InviteAcceptReadiness.documentRequired;
    case 'CONSENT_REQUIRED':
      return InviteAcceptReadiness.consentRequired;
    case 'REVIEW_PENDING':
      return InviteAcceptReadiness.reviewPending;
    case 'UNAVAILABLE':
      return InviteAcceptReadiness.unavailable;
    default:
      return InviteAcceptReadiness.unknown;
  }
}
