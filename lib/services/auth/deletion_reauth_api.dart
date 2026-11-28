// lib/services/auth/deletion_reauth_api.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 판정280 B280-02 · server_api_1 §5] 카카오 계정 탈퇴 재확인 서버 경계.
//
//   순서: callableDeletionReauthStart(로그인 필요) → requestId 를 KG merchant_uid 로 → KG 창 →
//         verifyPassAuth({purpose:'account_deletion', imp_uid}) → 서버가 `deletionReauthProofs/{uid}` 10분 기록
//         → 기존 삭제 파이프라인(PreData → Applications → Final).
//   이 증명은 작업(탈퇴)·UID 에 묶인다. 카카오 재로그인으로 받은 토큰은 증명이 아니다(B277-06).
//   users 문서가 이미 없는 삭제 재개도 같은 길이다(서버가 링크/증명으로 판별).

import 'package:cloud_functions/cloud_functions.dart';

import 'signup_api.dart';

class DeletionReauthTicket {
  const DeletionReauthTicket({required this.requestId, this.expiresAt});
  final String requestId;
  final DateTime? expiresAt;
}

abstract class DeletionReauthApi {
  /// 서버 requestId(KG merchant_uid)를 받는다.
  Future<DeletionReauthTicket> start();

  /// KG 결과를 서버가 확인한다. 반환 = 증명 만료 시각(모르면 null).
  Future<DateTime?> verify(String impUid);
}

class FirebaseDeletionReauthApi implements DeletionReauthApi {
  FirebaseDeletionReauthApi({FirebaseFunctions? functions})
      : _fn = functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  final FirebaseFunctions _fn;

  Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> body) async {
    try {
      final res = await _fn
          .httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
          .call<Object?>(body);
      final d = res.data;
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final d = e.details;
      final details = d is Map ? Map<String, dynamic>.from(d) : null;
      final reason = details?['reason'];
      throw SignupApiException(
          code: e.code, reason: reason is String ? reason : null, details: details);
    }
  }

  @override
  Future<DeletionReauthTicket> start() async {
    final data = await _call('callableDeletionReauthStart', const {});
    final id = data['requestId'];
    if (id is! String || id.isEmpty) {
      throw const SignupApiException(code: 'internal', reason: 'CERT_RESPONSE_INVALID');
    }
    final ms = data['expiresAtMs'];
    return DeletionReauthTicket(
      requestId: id,
      expiresAt: ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
    );
  }

  @override
  Future<DateTime?> verify(String impUid) async {
    final data = await _call('verifyPassAuth', {'purpose': 'account_deletion', 'imp_uid': impUid});
    if (data['proven'] != true) {
      // 성공 응답이 아니면 증명으로 쓰지 않는다.
      throw const SignupApiException(code: 'internal', reason: 'KG_NOT_CERTIFIED');
    }
    final ms = data['expiresAtMs'];
    return ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }
}
