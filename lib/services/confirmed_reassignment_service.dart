import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/core/confirmed_reassignment_proposal.dart';
import '../utils/global_loading_controller.dart';
import '../utils/network_checker.dart';
import '../utils/toast_helper.dart';

/// [CROSS-DOMAIN-R5.3E.2] 확정 근로자 업무 변경 제안.
///
/// 목록은 전부 CF를 거친다 — Charter의 list 쿼리 규칙 그대로다.
/// 제안 상태는 서버만 바꾼다. 화면은 성공/실패와 최신 목록만 읽는다.
class ConfirmedReassignmentService {
  static final ConfirmedReassignmentService instance =
      ConfirmedReassignmentService._();
  ConfirmedReassignmentService._();

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

  /// 근로자 — 변경을 수락한다. 이 호출이 성공한 순간에만 근무가 바뀐다.
  Future<bool> accept({
    required String proposalId,
    required String documentAccessConsentVersion,
  }) async {
    NetworkChecker.instance
        .assertOnline('변경을 수락하려면 인터넷 연결이 필요합니다.');
    GlobalLoadingController.show('변경을 반영하는 중...');
    try {
      await _fn('callableAcceptConfirmedReassignment', seconds: 30)
          .call<Map<String, dynamic>>({
        'proposalId': proposalId,
        'documentAccessConsentGiven': true,
        'documentAccessConsentVersion': documentAccessConsentVersion,
      });
      return true;
    } on FirebaseFunctionsException catch (e) {
      // 자리가 없거나 근무가 시작된 경우도 여기로 온다 —
      // 서버 문구가 이미 "기존 근무가 유지됩니다"를 말한다.
      debugPrint('❌ accept 실패: ${e.code} ${e.message}');
      ToastHelper.showError(e.message ?? '변경을 반영하지 못했습니다.');
      return false;
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
