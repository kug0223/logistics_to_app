import 'server_reject_codes.dart';

/// [impl_63 · 서버296–298] 근로자 화면이 받는 서버 거절 코드 → 짧은 안내.
///
///   판정은 공용 [serverRejectCodeOf](details['code'])만 쓴다 — 서버 문구 판별 0.
///   이 거절들은 '처리하지 않았다'(상태 그대로)이므로 일반 실패 · 성공으로 접지 않고, 다시 시도하면 되는 일이라고 말한다.

/// 초대 수락 — 확정 이력이 많아 근무 겹침 확인을 끝내지 못함(확정 0).
const String inviteOverlapCheckIncompleteMessage =
    '근무 겹침 확인을 끝내지 못해 수락하지 않았어요 · 다시 시도해 주세요';

/// 초대 수락 거절 안내 — 알려진 코드면 그 안내, 아니면 null(호출부가 서버 문구 · 기본 문구로).
String? inviteAcceptRejectMessageOf(Object error) =>
    serverRejectCodeOf(error) == ServerRejectCode.overlapCheckIncomplete
        ? inviteOverlapCheckIncompleteMessage
        : null;

/// 계약해지 요청 처리(거절 등) — 연결 계약을 끝까지 읽지 못함(처리 0).
String? terminationRejectMessageOf(Object error) =>
    serverRejectCodeOf(error) == ServerRejectCode.contractScanTruncated
        ? contractScanTruncatedMessage
        : null;
