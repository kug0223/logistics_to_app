// [APPROVE-REJECT-REASON] 지원 검토 `승인` 이 서버에서 거절됐을 때 관리자가 다음 행동을 알 수 있는 문장.
//
//   이전에는 모든 실패가 "승인 중 오류가 발생했습니다. 다시 시도해주세요." 였다 —
//   신분증 문턱(callableApproveApplicationForReview)에 막혀도 무엇을 해야 하는지 몰랐다.
//
//   규칙(확정 경로 day_applicants_dialog 와 같은 분류):
//     · failed-precondition — 서버가 판단해서 돌려준 사용자용 사유다.
//         신분증 문턱 두 가지는 **누가 해야 하는지**까지 말한다(아래 상수 = 서버 srvResolveMatchingReadiness 문구).
//         `POSTING_NOT_READY:` 코드는 접두어가 새지 않게 준비 단계 문장으로 바꾼다.
//         그 밖의 사유는 서버 문장을 그대로 쓴다(확정 경로와 같다).
//     · permission-denied / not-found — 화면의 기존 문장.
//     · 응답을 못 들은 코드(시간 초과·연결·internal·unknown)·그 밖 — 기존 일반 문구. 서버 원문·details 는 쓰지 않는다.
//         커밋됐을 수 있으므로 화면이 목록을 다시 읽는다([ApproveReviewError.reload]).
import 'package:cloud_functions/cloud_functions.dart';

import 'posting_readiness_reason.dart';

class ApproveReviewError {
  const ApproveReviewError(this.message, {required this.reload});

  /// 화면에 띄울 문장.
  final String message;

  /// 서버가 커밋했는지 모른다 — 목록을 다시 읽어 실제 상태를 보인다.
  final bool reload;

  /// 서버 판정 문구(srvResolveMatchingReadiness). 바뀌면 이 매핑은 서버 문장 그대로로 돌아간다.
  static const String serverIdMissing = '신분증이 등록되어 있지 않습니다.';
  static const String serverIdChanged = '신분증이 변경되어 다시 확인해야 합니다.';

  static const String idMissingText =
      '근로자가 아직 신분증을 등록하지 않아 확정할 수 없어요. 근로자가 신분증을 등록한 뒤 다시 확정해 주세요.';
  static const String idChangedText =
      '근로자가 신분증을 다시 올려 확인이 필요해요. 지원자 상세에서 신분증을 확인한 뒤 확정해 주세요.';
  static const String genericText = '확정 중 오류가 발생했습니다. 다시 시도해주세요.';

  static const Set<String> _uncertainCodes = {
    'deadline-exceeded', 'unavailable', 'cancelled', 'internal', 'unknown',
  };

  static ApproveReviewError of(Object error, {required bool canSetUp}) {
    if (error is! FirebaseFunctionsException) {
      return const ApproveReviewError(genericText, reload: true);
    }
    switch (error.code) {
      case 'failed-precondition':
        final blocked = PostingNotReady.parse(error);
        if (blocked != null) {
          return ApproveReviewError(blocked.confirmBlockedNotice(canSetUp: canSetUp), reload: false);
        }
        final m = (error.message ?? '').trim();
        if (m == serverIdMissing) return const ApproveReviewError(idMissingText, reload: false);
        if (m == serverIdChanged) return const ApproveReviewError(idChangedText, reload: false);
        return ApproveReviewError(m.isEmpty ? genericText : m, reload: false);
      case 'permission-denied':
        return const ApproveReviewError('이 사업장의 공고 관리 권한이 없습니다.', reload: false);
      case 'not-found':
        return const ApproveReviewError('지원서를 찾을 수 없습니다. 목록을 다시 불러옵니다.', reload: true);
    }
    return ApproveReviewError(genericText, reload: _uncertainCodes.contains(error.code));
  }
}
