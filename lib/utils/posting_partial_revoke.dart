import 'package:cloud_functions/cloud_functions.dart';

/// [POSTING-AUTH-45] 공고 작업 도중 권한이 회수돼 **앞 단계만 반영된** 거절인가.
///
///   서버(CloseSlots·DeleteSlots·DeleteTO)는 앞 단계 커밋 뒤 권한 확인이 막히면
///   permission-denied 와 함께 details.code = PERMISSION_REVOKED_MIDWAY 를 보낸다.
///   메시지는 일반 권한 거절과 같아서, 화면이 그 말만 띄우고 목록을 그대로 두면
///   이미 종료된 날짜·정리된 지원서가 보이지 않는다("변화 0"으로 읽힌다).
///   code 로만 판정한다 — 문구로 판별하지 않는다.
bool isPostingPartialRevoke(Object error) {
  if (error is! FirebaseFunctionsException) return false;
  if (error.code != 'permission-denied') return false;
  final details = error.details;
  return details is Map && details['code'] == 'PERMISSION_REVOKED_MIDWAY';
}

/// 부분 반영 거절 안내. 다시 시도하라고 하지 않는다 — 권한이 없어 재시도도 거절된다.
///   [POSTING-AUTH-46] 목록 갱신 결과를 단정하지 않는다. 갱신이 실패하면 목록 화면이 자기 실패
///   안내('새로고침하지 못했습니다' + 최신 아님 배너)를 따로 띄워 "일부 처리됨 · 최신 상태 확인 실패" 가 된다.
const String postingPartialRevokeMessage =
    '관리 권한이 바뀌어 일부만 처리되었어요. 최신 목록을 다시 불러옵니다.';
