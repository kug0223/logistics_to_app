import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// [R7-P1-2 DEVICE.1E.1] 명단 조회 결과를 무엇으로 말할 것인가 — 한 곳.
///
///   이 판정은 인력 현황 다이얼로그의 private State 안에 있었다. 계약은
///   contract test 가 소스 문자열로 고정하고 있었지만, **실행으로 증명된
///   적은 없었다**. 권한 회수와 조회 실패를 가르는 자리라 그 차이가 크다.
///
///   순수 함수로 떼어 내고 화면은 이것을 부른다 — 계산식을 테스트에
///   복사하지 않는다.

/// 조회 실패가 **권한 거부**였는가 — code 로만 판정한다.
///
///   메시지 문자열이나 화면 문구로 권한을 판별하지 않는다. 문구는 번역·
///   수정으로 바뀌고, 그때 보안 판정이 조용히 틀어진다.
bool isPermissionDenialError(Object error) {
  final String? code = switch (error) {
    FirebaseFunctionsException e => e.code,
    FirebaseException e => e.code,
    _ => null,
  };
  return code == 'permission-denied' || code == 'unauthenticated';
}

/// 이번 조회 뒤 화면이 가져야 할 상태.
///
/// [clearRows]      이미 보여 주던 명단을 지운다(권한 회수 확인).
/// [loadFailed]     보여 줄 것이 없다 — ERROR 화면.
/// [refreshFailed]  기존 명단은 유지하고 갱신 실패만 알린다(PARTIAL).
typedef ApplicantLoadOutcome = ({
  bool clearRows,
  bool loadFailed,
  bool refreshFailed,
});

/// [ok]      조회가 끝까지 성공했는가.
/// [denied]  **확인된** 권한 거부인가(code 기반).
/// [hadRows] 이전에 한 번이라도 명단을 받은 적이 있는가.
///
///   세 가지가 각각 다른 상태다.
///
///     성공            → 모두 해제
///     확인된 거부     → 지운다. stale rows + 배너 조합은 여기서 쓰지 않는다.
///                       볼 자격을 잃은 사람이 이름·연락처를 계속 보게 된다.
///     실패 + 기존행   → PARTIAL. 확정 직후 새로고침이 한 번 실패했다고
///                       방금까지 보던 명단을 통째로 지우지 않는다.
///     실패 + 최초     → ERROR. **읽지 못한 것과 없는 것은 다르다** —
///                       여기서 `지원자가 없습니다` 로 떨어지면 안 된다.
ApplicantLoadOutcome applicantLoadOutcome({
  required bool ok,
  required bool denied,
  required bool hadRows,
}) {
  if (ok) {
    return (clearRows: false, loadFailed: false, refreshFailed: false);
  }
  if (denied) {
    return (clearRows: true, loadFailed: false, refreshFailed: false);
  }
  if (hadRows) {
    return (clearRows: false, loadFailed: false, refreshFailed: true);
  }
  return (clearRows: false, loadFailed: true, refreshFailed: false);
}
