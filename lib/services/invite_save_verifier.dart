import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/ui/invite_refresh_outcome.dart';
import '../utils/toast_helper.dart';
import 'firestore_service.dart';

/// [E1-AMBIGUOUS-INVITE] 초대 저장을 시도한 뒤 응답이 불명확할 때, 서버에서
/// **대상 근로자의 이 공고 지원서**를 한 번 다시 읽어 저장 여부를 판단한다.
///
/// 결과는 셋이다 — 모름을 둘 중 하나로 접지 않는다.
///   [InviteSaveCheck.saved]    읽었고, 초대가 있다
///   [InviteSaveCheck.notSaved] 읽었고, 초대가 없다(지금 이 순간에는)
///   [InviteSaveCheck.unknown]  읽지 못했다 — 저장 실패도, 0건도 아니다
///
/// 읽기 경로는 지원자 관리 화면과 같은 `callableGetApplicationsByBiz`
/// (`purpose: applicantReview`)다. 새 권한이나 새 서버 코드가 필요 없다.
enum InviteSaveCheck { saved, notSaved, unknown }

/// 서버가 **결정적으로 거절한** 오류인가(쓰기 전에 던진 것).
///
/// callableInviteWorker 는 검사 → 트랜잭션 순서라, 아래 코드들은 모두
/// 트랜잭션 커밋 전에 던진다. 그 밖의 오류(시간 초과·연결 끊김·internal·
/// 알 수 없는 예외)는 요청이 서버에서 커밋됐는지 알 수 없다.
const Set<String> _definiteRejectCodes = {
  'invalid-argument',
  'failed-precondition',
  'permission-denied',
  'not-found',
  'already-exists',
  'resource-exhausted',
  'unauthenticated',
  'out-of-range',
};

/// 저장됐는지 모르는 실패인가.
bool isAmbiguousInviteError(Object e) {
  if (e is FirebaseFunctionsException) {
    return !_definiteRejectCodes.contains(e.code);
  }
  // 소켓 오류·TimeoutException 등 — 응답을 못 받았다.
  return true;
}

/// [PILOT-INVITE-FENCE-UI] 서버가 **시범 운영 차단**으로 새 근무 제안을 거절했는가.
///
///   펜스 후보(callableInviteWorker)는 `failed-precondition` + `details.reason`
///   `PILOT_INVITE_CREATE_BLOCKED` 로 거절한다(플러그인이 서버 details 를 그대로 넘긴다).
///   다시 보내도 결과가 같으므로 재시도를 권하지 않는다.
///   **그 reason 하나만** 본다 — 다른 failed-precondition 은 각자 기존 안내를 따른다.
bool isPilotInviteCreateBlockedError(Object e) {
  if (e is! FirebaseFunctionsException || e.code != 'failed-precondition') return false;
  final d = e.details;
  return d is Map && d['reason'] == 'PILOT_INVITE_CREATE_BLOCKED';
}

/// 시범 차단 안내 — 재시도 문구 없이 사실만 말한다.
const String kPilotInviteCreateBlockedMessage = '시범 운영 기간에는 새 근무 제안을 보낼 수 없습니다.';

/// `already-exists` 인가 — 불명확한 시도 뒤의 재시도가 이걸 받으면
/// 앞선 시도가 실제로 저장됐을 가능성이 있다.
bool isAlreadyExistsInviteError(Object e) =>
    e is FirebaseFunctionsException && e.code == 'already-exists';

typedef InviteApplicationsReader = Future<List<Map<String, dynamic>>>
    Function(Map<String, dynamic> params);

class InviteSaveVerifier {
  InviteSaveVerifier._();

  static InviteApplicationsReader _reader = fetchApplicationsByBizPaged;

  @visibleForTesting
  static set debugReader(InviteApplicationsReader? r) =>
      _reader = r ?? fetchApplicationsByBizPaged;

  /// 초대가 저장된 상태로 볼 수 있는 status.
  ///   INVITED — 방금 저장된 초대
  ///   CONFIRMED / CONTRACT_PENDING — 저장 뒤 이미 수락된 초대(invitedAt 있음)
  static const _invitedStatuses = {'INVITED', 'CONFIRMED', 'CONTRACT_PENDING'};

  static Future<InviteSaveCheck> check({
    required String businessId,
    required String toId,
    required String targetUid,
    String? slotId,
  }) async {
    if (businessId.isEmpty || toId.isEmpty || targetUid.isEmpty) {
      return InviteSaveCheck.unknown;
    }
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _reader({
        'businessId': businessId,
        'toId': toId,
        'uid': targetUid,
        'purpose': 'applicantReview',
        'limit': 20,
      });
    } catch (e) {
      debugPrint('⚠️ [E1] 초대 저장 확인 조회 실패: $e');
      return InviteSaveCheck.unknown;
    }
    final hit = rows.any((m) =>
        m['uid'] == targetUid &&
        m['toId'] == toId &&
        (slotId == null || slotId.isEmpty || m['slotId'] == slotId) &&
        _invitedStatuses.contains(m['status']) &&
        m['invitedAt'] != null);
    return hit ? InviteSaveCheck.saved : InviteSaveCheck.notSaved;
  }

  /// 닫힌 초대 다이얼로그의 결과를 서버 사실로 확정한다.
  ///
  /// [InviteRefreshOutcome.verify] 가 있으면 대상 지원서를 다시 읽고,
  /// **저장이 확인된 경우에만** 상위 전파를 켠다. 읽기에 실패하면 전파하지
  /// 않지만 목록 재조회(reload)는 그대로 둔다 — 목록은 자기 방식으로
  /// 성공·실패를 말한다.
  static Future<({InviteRefreshOutcome outcome, InviteSaveCheck? check})>
      resolve(InviteRefreshOutcome outcome, {required String businessId}) async {
    final v = outcome.verify;
    if (v == null) return (outcome: outcome, check: null);
    final c = await check(
      businessId: businessId,
      toId: v.toId,
      targetUid: v.targetUid,
      slotId: v.slotId,
    );
    return (
      outcome: InviteRefreshOutcome(
        propagate: c == InviteSaveCheck.saved,
        reload: outcome.reload,
      ),
      check: c,
    );
  }

  /// 닫힌 뒤 확인 결과를 관리자에게 알리는 문구.
  static String? closeMessage(InviteSaveCheck? c) => switch (c) {
        InviteSaveCheck.saved => '응답이 늦었지만 초대가 저장된 것을 확인했어요.',
        InviteSaveCheck.notSaved => '초대가 저장되지 않은 것으로 확인됐어요.',
        InviteSaveCheck.unknown =>
          '초대 저장 여부를 확인하지 못했어요. 잠시 후 목록을 새로고침해 확인해 주세요.',
        null => null,
      };

  static void announceClose(InviteSaveCheck? c) {
    final m = closeMessage(c);
    if (m == null) return;
    switch (c) {
      case InviteSaveCheck.saved:
        ToastHelper.showSuccess(m);
      case InviteSaveCheck.unknown:
        ToastHelper.showWarning(m);
      default:
        ToastHelper.showInfo(m);
    }
  }
}
