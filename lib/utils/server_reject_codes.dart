import 'package:cloud_functions/cloud_functions.dart';

import 'network_checker.dart'; // [impl_59] 오프라인 예외 안내

/// [impl_58 · server_296–298] 관리자 화면이 받는 서버 거절 코드 → 짧은 안내.
///
///   판정은 **`FirebaseFunctionsException.details['code']` 만** 본다(서버 문구 판별 0).
///   모르는 코드는 null — 호출부가 서버 문구(있으면) 또는 자기 기본 문구로 돌아간다.
///   거절 자체(저장 안 함 · 처리 안 함)는 그대로다 — 이 파일은 안내 문구만 고른다.
class ServerRejectCode {
  ServerRejectCode._();

  /// callableUpdateTO · callableCreateTO — 허용 목록 밖 항목(점/슬래시 키 · 서버 소유 필드)
  static const String toFieldNotAllowed = 'TO_FIELD_NOT_ALLOWED';

  /// 정원(requiredCount) 1–999 정수 — CreateTO · CreateFlexSlots · UpdateSlotWorkDetails · UpdateTO workDetails
  static const String requiredCountInvalid = 'REQUIRED_COUNT_INVALID';

  /// CreateFlexSlots — 달력에 없는 날짜(2월 30일 등)
  static const String invalidCalendarDate = 'INVALID_CALENDAR_DATE';

  /// CreateFlexSlots — 한 번에 366일 초과
  static const String tooManyDates = 'TOO_MANY_DATES';

  /// callableBatchCheckIn — 같은 근태에 내용이 다른 두 항목
  static const String checkInEntryConflict = 'CHECKIN_ENTRY_CONFLICT';

  /// callableCreateIdCardAccessRequest — 보낸 applicationId 가 이 근로자·사업장·확정 계열이 아님
  static const String applicationMismatch = 'APPLICATION_MISMATCH';

  /// callableUpdateWageDetail — 저장 맵에 있던 wageType/baseWage/baseAmount 누락·null
  static const String wageFieldMissing = 'WAGE_FIELD_MISSING';

  /// callableUpdateWageDetail — 시급/일급 유형 변경
  static const String wageTypeChanged = 'WAGE_TYPE_CHANGED';

  /// 중간정산(승인·처리·직접) — 근태 금액 형식 오류(급여 정정 필요)
  static const String wageValueInvalid = 'WAGE_VALUE_INVALID';

  /// 확정·초대 수락 — 확정 이력이 많아 겹침 확인을 끝내지 못함(확정 0)
  static const String overlapCheckIncomplete = 'OVERLAP_CHECK_INCOMPLETE';

  /// 계약해지 요청·취소·거절 — 연결 계약을 끝까지 읽지 못함(처리 0)
  static const String contractScanTruncated = 'CONTRACT_SCAN_TRUNCATED';
}

/// 서버 details.code. FirebaseFunctionsException 이 아니거나 code 가 없으면 null.
///   [PostingInputInvalid](앱의 같은 경계 사전 검사)도 같은 code 를 싣는다.
String? serverRejectCodeOf(Object error) {
  if (error is PostingInputInvalid) return error.code;
  if (error is! FirebaseFunctionsException) return null;
  final d = error.details;
  return (d is Map && d['code'] is String) ? d['code'] as String : null;
}

// ── 공고 입력 경계(서버와 같은 값) ────────────────────────────────────

/// 정원 하한·상한 — 서버 `srvAssertValidRequiredCount`(정수 1–999)와 같다.
const int kRequiredCountMin = 1;
const int kRequiredCountMax = 999;

/// 한 번에 등록하는 날짜 상한 — 서버 `SRV_FLEX_DATES_MAX`(366)와 같다.
const int kPostingDatesMaxPerRequest = 366;

bool isValidRequiredCount(Object? v) =>
    v is int && v >= kRequiredCountMin && v <= kRequiredCountMax;

final RegExp _ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// 'YYYY-MM-DD' 가 실제 달력 날짜인가 — 서버 `srvIsRealCalendarDate`(UTC 왕복)와 같은 판정.
bool isRealCalendarDateString(String s) {
  final m = _ymd.firstMatch(s);
  if (m == null) return false;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final dt = DateTime.utc(y, mo, d);
  return dt.year == y && dt.month == mo && dt.day == d;
}

/// 앱이 서버에 보내기 **전에** 같은 경계로 막은 입력. 서버 거절과 같은 code·같은 안내를 쓴다.
class PostingInputInvalid implements Exception {
  const PostingInputInvalid(this.code);
  final String code;
  @override
  String toString() => 'PostingInputInvalid($code)';
}

/// 공고 생성·수정 입력을 서버 경계로 미리 본다. 어긋나면 [PostingInputInvalid] 를 던진다.
///   [requiredCounts] 는 업무별 정원 · [dateStrings] 는 보낼 'YYYY-MM-DD' 목록(없으면 null).
void assertPostingInputWithinServerBounds({
  required Iterable<Object?> requiredCounts,
  List<String>? dateStrings,
}) {
  for (final c in requiredCounts) {
    if (!isValidRequiredCount(c)) {
      throw const PostingInputInvalid(ServerRejectCode.requiredCountInvalid);
    }
  }
  if (dateStrings != null) {
    if (dateStrings.length > kPostingDatesMaxPerRequest) {
      throw const PostingInputInvalid(ServerRejectCode.tooManyDates);
    }
    for (final s in dateStrings) {
      if (!isRealCalendarDateString(s)) {
        throw const PostingInputInvalid(ServerRejectCode.invalidCalendarDate);
      }
    }
  }
}

// ── 안내 문구 ─────────────────────────────────────────────────────────

const String toFieldNotAllowedMessage =
    '바꿀 수 없는 항목이 들어 있어 저장하지 않았어요 · 화면을 다시 열어 수정해 주세요';
const String requiredCountInvalidMessage =
    '필요 인원은 $kRequiredCountMin~$kRequiredCountMax명으로 입력해 주세요';
const String invalidCalendarDateMessage =
    '달력에 없는 날짜가 있어 저장하지 않았어요 · 날짜를 다시 골라 주세요';
const String tooManyDatesMessage =
    '날짜는 한 번에 $kPostingDatesMaxPerRequest일까지 등록할 수 있어요';
const String checkInEntryConflictMessage =
    '같은 출근 기록에 서로 다른 처리가 함께 들어와 처리하지 않았어요 · 최신 기록을 확인한 뒤 다시 시도해 주세요';
const String applicationMismatchMessage =
    '근무 정보가 이 근무자와 맞지 않아 요청하지 않았어요 · 목록을 새로 고친 뒤 다시 시도해 주세요';
const String wageFieldMissingMessage =
    '급여 정보 일부가 빠져 저장하지 않았어요 · 명세를 다시 열어 수정해 주세요';
const String wageTypeChangedMessage =
    '급여 유형(시급·일급)은 바꿀 수 없어 저장하지 않았어요';
const String wageValueInvalidMessage =
    '금액 형식이 잘못된 근무가 있어 처리하지 않았어요 · 급여 정정 뒤 다시 시도해 주세요';
const String overlapCheckIncompleteMessage =
    '근무 겹침 확인을 끝내지 못해 확정하지 않았어요 · 다시 시도해 주세요';
const String contractScanTruncatedMessage =
    '관련 계약을 모두 확인하지 못해 처리하지 않았어요 · 다시 시도해 주세요';

/// 공고 생성·수정(·슬롯 수정) 거절 4종.
String? postingInputRejectMessageOf(Object error) => switch (serverRejectCodeOf(error)) {
      ServerRejectCode.toFieldNotAllowed => toFieldNotAllowedMessage,
      ServerRejectCode.requiredCountInvalid => requiredCountInvalidMessage,
      ServerRejectCode.invalidCalendarDate => invalidCalendarDateMessage,
      ServerRejectCode.tooManyDates => tooManyDatesMessage,
      _ => null,
    };

/// 일괄 출근 거절.
String? batchCheckInRejectMessageOf(Object error) =>
    serverRejectCodeOf(error) == ServerRejectCode.checkInEntryConflict
        ? checkInEntryConflictMessage
        : null;

/// 신분증 열람 요청 거절.
String? idCardRequestRejectMessageOf(Object error) =>
    serverRejectCodeOf(error) == ServerRejectCode.applicationMismatch
        ? applicationMismatchMessage
        : null;

/// 급여 정정(callableUpdateWageDetail) 거절 3종.
String? wageUpdateRejectMessageOf(Object error) => switch (serverRejectCodeOf(error)) {
      ServerRejectCode.wageFieldMissing => wageFieldMissingMessage,
      ServerRejectCode.wageTypeChanged => wageTypeChangedMessage,
      ServerRejectCode.wageValueInvalid => wageValueInvalidMessage,
      _ => null,
    };

/// 중간정산 승인·처리·직접 정산의 금액 형식 거절.
String? wageValueInvalidMessageOf(Object error) =>
    serverRejectCodeOf(error) == ServerRejectCode.wageValueInvalid
        ? wageValueInvalidMessage
        : null;

/// 확정 거절(겹침 확인 미완료).
String? overlapCheckIncompleteMessageOf(Object error) =>
    serverRejectCodeOf(error) == ServerRejectCode.overlapCheckIncomplete
        ? overlapCheckIncompleteMessage
        : null;

/// 계약해지 처리 거절(연결 계약 확인 미완료).
String? contractScanTruncatedMessageOf(Object error) =>
    serverRejectCodeOf(error) == ServerRejectCode.contractScanTruncated
        ? contractScanTruncatedMessage
        : null;

/// 그 밖의 실패 — 서버 문구가 있으면 그것, 없으면 [fallback](예외 문자열 0).
String serverMessageOr(Object error, String fallback) {
  if (error is FirebaseFunctionsException && (error.message?.trim().isNotEmpty ?? false)) {
    return error.message!.trim();
  }
  return fallback;
}

// ── 지급정보 갱신(callableRefreshWagePaymentSnapshot) skipped 사유 ──────

/// [server_297 §3] 건별 거래에서 급여 권한이 회수되면 남은 건은 `permissionRevoked` 로 건너뛴다.
const String refreshSkippedPermissionRevoked = 'permissionRevoked';

String permissionRevokedSkippedLine(int n) => '권한이 바뀌어 처리하지 않은 $n건';

/// 건너뛴 건 안내 줄. 권한 회수는 건수와 함께 한 줄로 따로 말하고(급여계좌 문제로 뭉개지 않는다),
///   나머지는 [labelOf] 로 사유 이름을 붙여 중복 없이 나열한다.
List<String> refreshSkippedLines(
  Map<String, String> skipped,
  String Function(String code) labelOf,
) {
  final revoked = skipped.values.where((v) => v == refreshSkippedPermissionRevoked).length;
  final others = <String>{
    for (final v in skipped.values)
      if (v != refreshSkippedPermissionRevoked) labelOf(v),
  };
  return [
    if (revoked > 0) '• ${permissionRevokedSkippedLine(revoked)}',
    for (final l in others) '• $l',
  ];
}

// ── 신분증 열람 권한 회수 사유(callableCheckIdCardAccess · Batch) ─────────

/// [server_296 §2] approved 였지만 지금 쓸 수 없어 'revoked' 로 내려온 이유(unusableReason) 중 관리자가 다시 요청해
///   풀 수 있는 두 가지. 그 밖의 사유(소속 아님·지원서 비확정)는 기존 표시 그대로다.
const String idCardUnusableLegacyAutoGrant = 'LEGACY_AUTO_GRANT';
const String idCardUnusableManualGrantExpired = 'MANUAL_GRANT_EXPIRED';

/// [impl_59 · server_296 §2] 나머지 두 사유 — 요청한 사업장이 지금 소속(관리) 사업장이 아님 · 열람권의 지원서가 확정 계열이 아님.
///   예전에는 'none'(신분증미요청)으로 접혀 요청한 적 없는 사람처럼 읽혔다.
const String idCardUnusableNotCurrentMember = 'NOT_CURRENT_MEMBER';
const String idCardUnusableApplicationInactive = 'GRANT_APPLICATION_INACTIVE';

// ── 일괄 확정 · 확정 취소 결과 안내 ──────────────────────────────────

/// 일괄 확정 중 겹침 확인을 끝내지 못해 확정하지 않은 건수 한 줄.
String overlapIncompleteBatchNote(int n) => '근무 겹침 확인을 끝내지 못해 확정하지 않은 $n명 · 다시 시도해 주세요';

/// 확정 취소 서비스가 false(서버 거절 · 결과 확인 불가)를 돌려준 뒤 — 성공이라 말하지 않고 다시 읽은 상태를 보게 한다.
const String confirmCancelNotDoneMessage = '확정을 취소하지 못했어요 · 목록을 다시 불러왔으니 상태를 확인해 주세요';

// ── [impl_59] 확정 취소 결과 · 관리자 처리 실패 공용 안내 ─────────────────

/// 결과를 알 수 없는 HttpsError code — 서버가 처리했는지 모른다(실패라고 단정하지 않는다).
const Set<String> serverOutcomeUnknownCodes = {'deadline-exceeded', 'unavailable', 'internal', 'unknown', 'cancelled', 'aborted'};

/// 서버 문구를 화면에 그대로 보여도 되는가 — 비어 있지 않고, 내부 꼬리표('[…]')나 영문 식별자(4자 이상 · 밑줄)가 섞이지 않은 문장.
///   **판정(어떤 거절인가)에는 쓰지 않는다** — 판정은 details.code · HttpsError code 로만 한다. 이것은 표시 안전 거르기다
///   (예: '[Fix-A] new-schema slot에서 wdId…' · 'attendanceIds가 필요합니다' 같은 개발 문장을 걸러 낸다).
bool isUserFacingServerMessage(String? message) {
  final m = message?.trim() ?? '';
  if (m.isEmpty || m.startsWith('[')) return false;
  return !RegExp(r'[A-Za-z_]{4,}').hasMatch(m);
}

/// 관리자 처리 실패 안내 한 줄 — 예외 문자열(`$e`)을 붙이지 않는다.
///   ① details.code 가 [byCode] 에 있으면 그 안내 ② 오프라인이면 연결 안내
///   ③ 결과를 아는 서버 거절이고 문구가 보여도 되는 문장이면 서버 문구 ④ 나머지(시간 초과·연결 끊김·내부 오류·모르는 예외)는 [fallback].
String adminActionErrorMessage(Object error, {required String fallback, Map<String, String> byCode = const {}}) {
  final code = serverRejectCodeOf(error);
  if (code != null && byCode[code] != null) return byCode[code]!;
  if (error is NetworkOfflineException) return error.message;
  if (error is FirebaseFunctionsException &&
      !serverOutcomeUnknownCodes.contains(error.code) &&
      isUserFacingServerMessage(error.message)) {
    return error.message!.trim();
  }
  return fallback;
}

// 관리자 처리 실패 기본 안내([adminActionErrorMessage] 의 fallback) — 결과를 모르면 다시 읽은 상태를 보게 한다.
const String transferMarkFailedMessage = '이체 완료 처리를 하지 못했어요 · 목록을 다시 불러왔으니 상태를 확인해 주세요';
const String transferBatchFailedMessage = '일괄 이체 처리를 하지 못했어요 · 목록을 다시 불러왔으니 상태를 확인해 주세요';
const String interimRejectFailedMessage = '중간정산을 거절하지 못했어요 · 잠시 뒤 다시 시도해 주세요';
const String interimApprovalCancelFailedMessage = '중간정산 승인을 취소하지 못했어요 · 잠시 뒤 다시 시도해 주세요';
const String transferCancelFailedMessage = '이체 완료 처리를 취소하지 못했어요 · 잠시 뒤 다시 시도해 주세요';
const String noshowReleaseFailedMessage = '빈자리 다시 모집을 하지 못했어요 · 목록을 새로 고친 뒤 다시 시도해 주세요';
const String contractSendFailedMessage = '계약서를 보내지 못했어요 · 계약서 목록에서 상태를 확인해 주세요';
const String applicantRejectFailedMessage = '지원을 거절하지 못했어요 · 목록을 새로 고친 뒤 다시 시도해 주세요';

const String confirmCancelUnknownMessage ='확정 취소 결과를 확인하지 못했어요 · 목록에서 상태를 확인해 주세요';
const String confirmCancelUnknownReloadedMessage = '확정 취소 결과를 확인하지 못했어요 · 목록을 다시 불러왔으니 상태를 확인해 주세요';
const String confirmCancelNotFoundMessage = '지원서를 찾을 수 없어 취소하지 않았어요 · 목록을 새로 고쳐 주세요';
const String confirmCancelPermissionMessage = '확정을 취소할 권한이 없어요';
const String confirmCancelRejectedFallback = '확정을 취소하지 못했어요 · 목록을 새로 고친 뒤 다시 시도해 주세요';

/// [impl_59] 확정 취소 한 건의 결과.
///   예전에는 bool 이었다. 서비스가 구체 사유 토스트를 띄운 뒤 false 를 돌려주면, 화면이 일반 실패 안내로 그 사유를 덮었다.
///   이제 서비스는 토스트를 띄우지 않고 사유를 돌려준다 — 안내는 화면이 한 번만 띄운다.
class ConfirmCancelResult {
  final bool success;

  /// 취소됐는지 알 수 없다(시간 초과·연결 끊김·응답 이상). 화면은 실패라고 단정하지 않고 다시 읽은 상태를 보게 한다.
  final bool outcomeUnknown;

  /// details.code 가 있으면 그것, 없으면 HttpsError code(오프라인 = 'offline'). 기록·시험용 — 화면 문구 판별에 쓰지 않는다.
  final String? code;

  /// 사용자에게 보일 한 줄(성공이면 빈 문자열).
  final String message;

  const ConfirmCancelResult._({required this.success, required this.outcomeUnknown, this.code, required this.message});

  const ConfirmCancelResult.succeeded() : this._(success: true, outcomeUnknown: false, message: '');

  /// CF 는 성공으로 답했지만 응답이 이상하다(근무자 uid 없음 등) — 결과 모름.
  const ConfirmCancelResult.unknown([String? code])
      : this._(success: false, outcomeUnknown: true, code: code, message: confirmCancelUnknownMessage);

  /// 예외 → 결과. 서버 거절(결과 앎)은 이유를, 시간 초과·모르는 예외는 '결과 모름'을 돌려준다.
  factory ConfirmCancelResult.fromError(Object error) {
    if (error is NetworkOfflineException) {
      return ConfirmCancelResult._(success: false, outcomeUnknown: false, code: 'offline', message: error.message);
    }
    if (error is! FirebaseFunctionsException) return const ConfirmCancelResult.unknown();
    final code = serverRejectCodeOf(error) ?? error.code;
    if (serverOutcomeUnknownCodes.contains(error.code)) return ConfirmCancelResult.unknown(code);
    final message = switch (error.code) {
      'not-found' => confirmCancelNotFoundMessage,
      'permission-denied' => confirmCancelPermissionMessage,
      _ => adminActionErrorMessage(error, fallback: confirmCancelRejectedFallback),
    };
    return ConfirmCancelResult._(success: false, outcomeUnknown: false, code: code, message: message);
  }

  /// 관리자 목록 화면이 다시 읽은 뒤 띄우는 실패 안내 — 결과 모름이면 다시 불러온 상태를 보라고 말한다.
  String get adminToast => outcomeUnknown ? confirmCancelUnknownReloadedMessage : message;
}
