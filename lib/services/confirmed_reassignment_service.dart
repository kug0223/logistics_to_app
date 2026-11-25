import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/core/confirmed_reassignment_proposal.dart';
import '../utils/global_loading_controller.dart';
import '../utils/network_checker.dart';
import '../utils/toast_helper.dart';

/// [CONSENT-R4] 근로자 변경 수락 결과 — '동의가 필요하다'를 실패와 나눈다.
///
///   accepted        서버가 B 를 확정했다.
///   consentRequired 서버가 원 근무의 동의를 승계할 수 없다고 답했다(쓰기 0 · 제안 열림).
///                   시트가 같은 자리에서 v4 카드를 보여주고 명시 동의를 받는다. 토스트 0.
///   failed          그 밖의 실패(대상 불가·기한·권한 등) — 서버 문구를 토스트로 보인다.
enum ReassignAcceptResult { accepted, consentRequired, failed }

/// [CROSS-DOMAIN-R5.3E.2] 확정 근로자 업무 변경 제안.
///
/// 목록은 전부 CF를 거친다 — Charter의 list 쿼리 규칙 그대로다.
/// 제안 상태는 서버만 바꾼다. 화면은 성공/실패와 최신 목록만 읽는다.
class ConfirmedReassignmentService {
  static final ConfirmedReassignmentService instance =
      ConfirmedReassignmentService._();
  ConfirmedReassignmentService._();

  /// [CONSENT-R4] 시험 전용 호출 대체 — null 이면 실제 Cloud Functions 를 부른다.
  ///   payload 모양(INHERIT / EXPLICIT)을 하네스가 그대로 관측하기 위한 자리다.
  @visibleForTesting
  static Future<Object?> Function(String name, Map<String, dynamic> payload)?
      debugCall;

  HttpsCallable _fn(String name, {int seconds = 20}) =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3').httpsCallable(
        name,
        options: HttpsCallableOptions(timeout: Duration(seconds: seconds)),
      );

  List<ConfirmedReassignmentProposal> _parse(Object? data) {
    final map = Map<String, dynamic>.from(data as Map);
    final raw = (map['proposals'] as List?) ?? const [];
    return raw
        .whereType<Map>()
        .map((e) => ConfirmedReassignmentProposal.tryFromMap(
            Map<String, dynamic>.from(e)))
        .whereType<ConfirmedReassignmentProposal>()
        .toList();
  }

  /// 근로자 — 나에게 온 진행 중인 변경 제안.
  ///
  /// 실패를 빈 목록으로 바꾸지 않는다. 제안이 없는 것과 못 읽은 것은 다르다.
  Future<List<ConfirmedReassignmentProposal>> myProposals() async {
    final r = await _fn('callableGetMyConfirmedReassignmentProposals')
        .call<Map<String, dynamic>>({});
    return _parse(r.data);
  }

  /// 관리자 — 이 사업장의 변경 제안.
  Future<List<ConfirmedReassignmentProposal>> proposalsByBusiness(
    String businessId, {
    bool includeTerminal = false,
  }) async {
    final r = await _fn('callableGetConfirmedReassignmentProposalsByBiz')
        .call<Map<String, dynamic>>({
      'businessId': businessId,
      'includeTerminal': includeTerminal,
    });
    return _parse(r.data);
  }

  /// 관리자 — 확정된 근무(A)에 다른 업무(B)를 제안한다.
  ///
  /// 성공해도 A는 바뀌지 않는다 — 근로자가 수락할 때까지 그대로다.
  Future<String?> propose({
    required String sourceApplicationId,
    required String targetWdId,
    required String compensationOption,
  }) async {
    NetworkChecker.instance
        .assertOnline('변경 제안을 보내려면 인터넷 연결이 필요합니다.');
    GlobalLoadingController.show('변경 제안을 보내는 중...');
    try {
      final r = await _fn('callableProposeConfirmedReassignment')
          .call<Map<String, dynamic>>({
        'sourceApplicationId': sourceApplicationId,
        'targetWdId': targetWdId,
        'compensationOption': compensationOption,
      });
      final m = Map<String, dynamic>.from(r.data as Map);
      return m['proposalId'] as String?;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ propose 실패: ${e.code} ${e.message}');
      ToastHelper.showError(e.message ?? '변경 제안에 실패했습니다.');
      return null;
    } finally {
      GlobalLoadingController.hide();
    }
  }

  /// [CONSENT-R4] 수락 payload — 두 방식을 섞지 않는다.
  ///
  ///   [shownConsentVersion] == null → INHERIT(첫 호출). 동의 값을 보내지 않는다 —
  ///     서버가 원 근무의 저장 동의를 승계할 수 있는지 본다.
  ///   != null → EXPLICIT. 시트가 방금 보여준 카드의 판본과 명시 동의를 보낸다.
  @visibleForTesting
  static Map<String, dynamic> acceptPayload(
    String proposalId, {
    String? shownConsentVersion,
  }) =>
      <String, dynamic>{
        'proposalId': proposalId,
        if (shownConsentVersion == null)
          'consentMode': 'INHERIT'
        else ...<String, dynamic>{
          'consentMode': 'EXPLICIT',
          'documentAccessConsentGiven': true,
          'documentAccessConsentVersion': shownConsentVersion,
          'consentShown': true,
        },
      };

  /// 서버가 details.code = CONSENT_REQUIRED 로 답했는가(Map 이 아니면 아니다).
  @visibleForTesting
  static bool isConsentRequired(Object? details) =>
      details is Map && details['code'] == 'CONSENT_REQUIRED';

  /// 근로자 — 변경을 수락한다. 이 호출이 성공한 순간에만 근무가 바뀐다.
  Future<ReassignAcceptResult> accept({
    required String proposalId,
    String? shownConsentVersion,
  }) async {
    NetworkChecker.instance
        .assertOnline('변경을 수락하려면 인터넷 연결이 필요합니다.');
    GlobalLoadingController.show('변경을 반영하는 중...');
    final payload =
        acceptPayload(proposalId, shownConsentVersion: shownConsentVersion);
    try {
      final call = debugCall;
      if (call != null) {
        await call('callableAcceptConfirmedReassignment', payload);
      } else {
        await _fn('callableAcceptConfirmedReassignment', seconds: 30)
            .call<Map<String, dynamic>>(payload);
      }
      return ReassignAcceptResult.accepted;
    } on FirebaseFunctionsException catch (e) {
      if (isConsentRequired(e.details)) {
        // 실패가 아니다 — 시트가 카드와 '동의하고 변경 수락'을 보인다. 토스트 0.
        debugPrint('ℹ️ accept: 서류 열람 동의 필요 (${e.details})');
        return ReassignAcceptResult.consentRequired;
      }
      // 자리가 없거나 근무가 시작된 경우도 여기로 온다 —
      // 서버 문구가 이미 "기존 근무가 유지됩니다"를 말한다.
      debugPrint('❌ accept 실패: ${e.code} ${e.message}');
      ToastHelper.showError(e.message ?? '변경을 반영하지 못했습니다.');
      return ReassignAcceptResult.failed;
    } finally {
      GlobalLoadingController.hide();
    }
  }

  /// 근로자 — 기존 조건을 유지한다.
  Future<bool> decline(String proposalId) async {
    GlobalLoadingController.show('처리 중...');
    try {
      await _fn('callableDeclineConfirmedReassignment')
          .call<Map<String, dynamic>>({'proposalId': proposalId});
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ decline 실패: ${e.code} ${e.message}');
      ToastHelper.showError(e.message ?? '처리에 실패했습니다.');
      return false;
    } finally {
      GlobalLoadingController.hide();
    }
  }

  /// 관리자 — 보낸 제안을 철회한다.
  Future<bool> cancel(String proposalId) async {
    GlobalLoadingController.show('제안을 철회하는 중...');
    try {
      await _fn('callableCancelConfirmedReassignment')
          .call<Map<String, dynamic>>({'proposalId': proposalId});
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ cancel 실패: ${e.code} ${e.message}');
      ToastHelper.showError(e.message ?? '철회에 실패했습니다.');
      return false;
    } finally {
      GlobalLoadingController.hide();
    }
  }
}
