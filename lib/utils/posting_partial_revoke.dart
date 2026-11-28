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

/// [판정294 F294-CLOSE-01 · F294-DEL-01] 앞 단계는 커밋됐고 **남은 정리가 끝나지 않은** 거절인가.
///
///   서버는 이때 `aborted` 와 함께 details.code 를 보낸다.
///   - CloseSlots: `CLOSE_SLOTS_INCOMPLETE` (날짜 종료는 반영 · 일부 대기 정리·공고 상태 갱신이 남음 · `failedSlotIds`)
///   - DeleteTO·DeleteSlots: `CLEANUP_INCOMPLETE` (지원서별 정리 일부 반영 · 공고/날짜는 아직 지우지 않음)
///   같은 요청을 다시 보내면 남은 것만 처리된다. 일반 실패 토스트로 뭉개면 이미 바뀐 목록이 안 보이고
///   (변화 0 으로 읽힌다) 다시 시도할 이유도 모른다. code 로만 판정한다 — 문구로 판별하지 않는다.
const Set<String> postingIncompleteCodes = {'CLOSE_SLOTS_INCOMPLETE', 'CLEANUP_INCOMPLETE'};

bool isPostingIncomplete(Object error) {
  if (error is! FirebaseFunctionsException) return false;
  if (error.code != 'aborted') return false;
  final details = error.details;
  return details is Map && postingIncompleteCodes.contains(details['code']);
}

/// [POSTING-RACE-46 · 판정294] 관계 확인 뒤 새로 들어온 지원 때문에 삭제가 막혔다.
///   그 사이 늦은 지원서 정리(대기 거절 등)는 반영됐을 수 있어 목록을 새로 읽어야 한다.
///   안내 문구는 서버 메시지(기존 '…기록이 있어 삭제할 수 없습니다 …종료를 이용해주세요')를 그대로 쓴다.
bool isPostingRelationAfterCheck(Object error) {
  if (error is! FirebaseFunctionsException) return false;
  if (error.code != 'failed-precondition') return false;
  final details = error.details;
  return details is Map && details['code'] == 'RELATION_AFTER_CHECK';
}

/// CloseSlots 재시도 대상. 서버가 실패 슬롯을 알려 주면 그것만, 공고 상태 갱신만 남았거나 모르면 처음 요청 그대로.
///   서버는 이미 종료한 날짜를 다시 받아도 같은 값으로 기록하므로 처음 요청을 다시 보내도 안전하다.
List<String> postingIncompleteRetrySlotIds(Object error, {required List<String> fallback}) {
  if (error is FirebaseFunctionsException) {
    final details = error.details;
    if (details is Map) {
      final raw = details['failedSlotIds'];
      if (raw is List) {
        final ids = raw.whereType<String>().where((s) => s.isNotEmpty && fallback.contains(s)).toSet().toList();
        if (ids.isNotEmpty) return ids;
      }
    }
  }
  return fallback;
}

/// 삭제(공고·날짜) 일부 정리 안내 — 공고/날짜는 남아 있고 같은 삭제를 다시 하면 남은 것만 처리된다.
const String postingDeleteIncompleteMessage =
    '일부만 처리되었어요. 다시 삭제하면 남은 것만 이어서 처리해요.';

/// 날짜 종료 일부 정리 안내(남은 것이 대기 정리든 공고 상태 갱신이든 같은 말) — 종료한 날짜는 종료 선택 목록에 다시 나오지 않으므로 이 자리에서 다시 시도를 제안한다.
const String postingCloseIncompleteTitle = '일부만 처리되었어요';
const String postingCloseIncompleteMessage =
    '날짜 종료는 반영됐지만 남은 정리를 마치지 못했어요.\n다시 정리를 눌러 같은 요청을 다시 보내 주세요(남은 것만 처리해요).';

/// [F295-CLOSE-01 · impl_41] 미완료 거절의 `details.resumable`.
///   true = 서버에 남은 표식이 이어서 정리한다(매시) · false = 표식이 없어 같은 요청을 다시 보내야 한다 · null = 구서버(모름 → false 처럼 안내).
bool? postingCloseResumable(Object error) {
  if (error is! FirebaseFunctionsException) return null;
  final d = error.details;
  if (d is Map && d['resumable'] is bool) return d['resumable'] as bool;
  return null;
}

/// resumable:true 안내 — 자동으로 이어지지만 지금 바로 다시 정리할 수도 있다(다시 정리 버튼 유지).
const String postingCloseAutoResumeMessage =
    '날짜 종료는 반영됐고 남은 정리는 자동으로 이어서 처리해요.\n지금 바로 다시 정리할 수도 있어요.';

/// 미완료 안내 문구 — resumable 에 따라 고른다(false·모름 = [postingCloseIncompleteMessage]).
String postingCloseIncompleteMessageFor(Object error) =>
    postingCloseResumable(error) == true ? postingCloseAutoResumeMessage : postingCloseIncompleteMessage;

/// 성공 응답의 `notClosedSlotIds`(cleanupOnly · 그 사이 다시 열려 정리하지 않은 날짜). 없거나 모양이 틀리면 빈 목록.
List<String> postingNotClosedSlotIds(Map<String, dynamic> response) {
  final raw = response['notClosedSlotIds'];
  if (raw is! List) return const [];
  return raw.whereType<String>().where((s) => s.isNotEmpty).toSet().toList();
}

/// [판정294 F294-CLOSE-01] 날짜 종료 '다시 시도' 결과.
enum PostingCloseRetryOutcome {
  /// 사용자가 '나중에'를 골랐다(또는 화면이 사라졌다) — 아무것도 보내지 않았다.
  declined,

  /// 다시 보낸 요청이 성공했다 — 남은 정리를 마쳤다.
  completed,

  /// 다시 보낸 요청이 권한 회수로 일부만 반영됐다(PERMISSION_REVOKED_MIDWAY).
  revoked,

  /// 다시 보낸 요청이 그 밖의 이유로 실패했다.
  failed,
}

/// [판정294 F294-CLOSE-01] CLOSE_SLOTS_INCOMPLETE 뒤 다시 시도 고리(화면과 분리 · 가짜 callable 로 시험).
///   - 매번 [ask] 로 묻고(마지막 거절을 넘긴다 — resumable 에 따라 문구를 고른다), 예면 [send] 로 남은 대상을 다시 보낸다.
///     [send] 는 cleanupOnly 로 보낸다(impl_41 — 최초 종료 기록을 덮지 않는다).
///   - 보낸 뒤에는 성공·실패와 무관하게 [refresh](목록 새로 읽기) — 다시 보낸 요청도 일부 반영될 수 있다.
///   - 또 미완료면 다시 묻는다. 묻는 횟수에 상한을 두지 않는다(사용자가 '나중에'로 끝낸다).
Future<(PostingCloseRetryOutcome, Object?)> runPostingCloseRetry({
  required Object initialError,
  required List<String> slotIds,
  required Future<bool> Function(Object error) ask,
  required Future<void> Function(List<String> ids) send,
  required void Function() refresh,
  required bool Function() isMounted,
}) async {
  Object lastError = initialError;
  while (isMounted() && isPostingIncomplete(lastError)) {
    final ids = postingIncompleteRetrySlotIds(lastError, fallback: slotIds);
    final again = await ask(lastError);
    if (!again || !isMounted()) return (PostingCloseRetryOutcome.declined, null);
    try {
      await send(ids);
      if (!isMounted()) return (PostingCloseRetryOutcome.completed, null);
      refresh();
      return (PostingCloseRetryOutcome.completed, null);
    } catch (e) {
      if (!isMounted()) return (PostingCloseRetryOutcome.failed, e);
      refresh();
      lastError = e;
      if (isPostingIncomplete(e)) continue;
      return (isPostingPartialRevoke(e) ? PostingCloseRetryOutcome.revoked : PostingCloseRetryOutcome.failed, e);
    }
  }
  return (PostingCloseRetryOutcome.declined, null);
}
