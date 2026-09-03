import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
// iamport_flutter 0.10.21 API 구조:
//   - IamportCertification.certification() static 메서드 없음
//   - IamportCertification은 StatelessWidget — Navigator.push로 표시
//   - callback 파라미터는 Map<String, String> (IamportResponse 클래스 없음)
//     { 'success': 'true'|'false', 'imp_uid': '...', 'error_msg': '...' }
import 'package:iamport_flutter/Iamport_certification.dart';
import 'package:iamport_flutter/model/certification_data.dart';
import 'package:iamport_flutter/model/url_data.dart';
import '../utils/navigation_key.dart';
import '../utils/toast_helper.dart';

/// PASS 본인인증 결과 데이터
class PassAuthResult {
  final String name;
  final String gender;       // '남성' | '여성'
  final DateTime birthDate;
  final String phone;
  final String passToken;    // 15분 유효, 가입/비밀번호 찾기 시 CF로 전달

  const PassAuthResult({
    required this.name,
    required this.gender,
    required this.birthDate,
    required this.phone,
    required this.passToken,
  });
}

/// PASS 본인인증 서비스 — PortOne(포트원) V1 SDK 기반
///
/// 흐름:
///   authenticate()
///     → IamportCertification 위젯을 Navigator에 fullscreen push
///     → KG이니시스 통합인증 V1 WebView 표시
///     → 사용자 인증 완료 → callback(`Map<String, String>`) 호출 → pop
///     → CF verifyPassAuth(imp_uid) → PassAuthResult 반환
///
class PassVerificationService {
  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// PortOne V1 고객사 식별코드 (포트원 콘솔 > 식별코드·API Keys > V1 API)
  static const _portoneUserCode = 'imp73242783';

  /// KG이니시스 본인인증 PG 코드
  /// 테스트: 'inicis_unified.MIIiasTest'
  /// 실연동: 계약 후 발급받은 MID로 교체 (예: 'inicis_unified.실제MID')
  static const _pgCode = 'inicis_unified.MIIiasTest';

  /// PASS 인증 실행
  ///
  /// [purpose]: 'register' (가입) | 'resetPassword' (비밀번호 찾기)
  /// [role]: 'USER' | 'BUSINESS_ADMIN' (가입 시 CF에서 중복 체크에 사용)
  ///
  /// 반환값이 null이면 사용자가 인증을 취소하거나 오류가 발생한 것입니다.
  static Future<PassAuthResult?> authenticate({
    required String purpose,
    String role = 'USER',
  }) async {
    final merchantUid = 'alfit_cert_${DateTime.now().millisecondsSinceEpoch}';

    // navigatorKey가 아직 MaterialApp에 연결되지 않은 경우 무음 실패 방지
    final navState = navigatorKey.currentState;
    if (navState == null) {
      ToastHelper.showError('화면 상태를 불러올 수 없습니다. 앱을 재시작해주세요');
      return null;
    }

    // IamportCertification 위젯을 Navigator에 push.
    // callback이 호출되면 결과 Map을 pop()으로 반환하고 여기서 await 해제.
    // 사용자가 뒤로가기로 취소하면 callback 미호출 → result == null 반환.
    final result = await navState.push<Map<String, String>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => IamportCertification(
          userCode: _portoneUserCode,
          data: CertificationData(
            pg: _pgCode,
            merchantUid: merchantUid,
            name: '',
            phone: '',
            minAge: 19,
            // KG이니시스 통합인증 필수 파라미터.
            // null이면 toJson()에서 키 자체가 생략되어 PG 측에서 에러 반환.
            // iamport_flutter WebView가 이 URL을 감지해 콜백을 호출하므로
            // 실제 HTTP 요청이 발생하지 않는 내부 인터셉트 URL.
            mRedirectUrl: UrlData.redirectUrl,
          ),
          callback: (Map<String, String> response) {
            // 인증 WebView 완료 후 호출됨. pop으로 result 전달.
            navigatorKey.currentState?.pop(response);
          },
        ),
      ),
    );

    if (result == null) return null; // 사용자 취소

    final success = result['success'] == 'true';
    if (!success) {
      final errorMsg = result['error_msg'];
      debugPrint('[PassAuth] WebView 인증 실패: error_msg=$errorMsg, result=$result');
      if (errorMsg != null && errorMsg.isNotEmpty) {
        ToastHelper.showError(errorMsg);
      }
      return null;
    }

    final impUid = result['imp_uid'];
    if (impUid == null || impUid.isEmpty) {
      debugPrint('[PassAuth] imp_uid 없음: result=$result');
      ToastHelper.showError('본인인증 결과를 받지 못했습니다');
      return null;
    }

    // CF verifyPassAuth: PortOne imp_uid를 검증하고 passToken 발급
    try {
      final cfResult = await _fn
          .httpsCallable(
            'verifyPassAuth',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call({
        'imp_uid': impUid,
        'purpose': purpose,
        'role': role,
      });

      final data = Map<String, dynamic>.from(cfResult.data as Map);
      final name        = data['name']      as String?;
      final gender      = data['gender']    as String?;
      final birthDateStr = data['birthDate'] as String?;
      final phone       = data['phone']     as String?;
      final passToken   = data['passToken'] as String?;

      if (name == null || gender == null || birthDateStr == null ||
          phone == null || passToken == null) {
        debugPrint('[PassAuth] CF 응답 필드 누락: name=$name, gender=$gender, birthDate=$birthDateStr, phone=$phone, passToken=${passToken != null}');
        ToastHelper.showError('본인인증 결과를 받지 못했습니다');
        return null;
      }

      final birthDate = _parseBirthDate(birthDateStr);
      if (birthDate == null) {
        debugPrint('[PassAuth] 생년월일 파싱 실패: birthDateStr=$birthDateStr');
        ToastHelper.showError('본인인증 결과를 받지 못했습니다');
        return null;
      }

      return PassAuthResult(
        name: name,
        gender: gender,
        birthDate: birthDate,
        phone: phone,
        passToken: passToken,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[PassAuth] CF 오류: code=${e.code}, message=${e.message}, details=${e.details}');
      ToastHelper.showError(_mapCfError(e.code));
      return null;
    } catch (e) {
      debugPrint('[PassAuth] 예외: $e');
      ToastHelper.showError('본인인증 처리 중 오류가 발생했습니다');
      return null;
    }
  }

  /// 가입 완료 후 passToken 소비 + ciHash 저장 — [AUTH-H3] 15분 재사용 차단
  ///
  /// 가입 성공 직후 호출한다. 실패해도 가입 자체는 완료된 상태이므로 예외를 삼킨다.
  static Future<void> finalizeRegistration(String passToken) async {
    try {
      await _fn
          .httpsCallable(
            'finalizeRegistration',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
          )
          .call({'passToken': passToken});
    } catch (e) {
      debugPrint('⚠️ [PassVerificationService] finalizeRegistration 실패: $e');
      // best-effort — 가입 완료를 막지 않음. passToken은 15분 후 TTL로 자동 만료됨.
    }
  }

  /// 재인증(설정 > 본인인증 / 홈 배너) 완료 후 passToken 소비 + ciHash/passVerifiedAt 저장
  ///
  /// [H-5] ciHash·passVerifiedAt은 클라이언트에서 직접 write 불가 — CF Admin SDK 경유 필수.
  /// 성공 시 users/{uid}.passVerifiedAt = serverTimestamp() 업데이트 → needsPassAuthRecovery 해제.
  /// 실패 시 예외를 호출자에게 그대로 전달한다 (재인증 미완료 상태를 유지해야 하므로 삼키지 않음).
  static Future<void> finalizePassReauth(String passToken) async {
    await _fn
        .httpsCallable(
          'finalizePassReauth',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
        )
        .call({'passToken': passToken});
  }

  // ── 유틸 ───────────────────────────────────────────────────────────────────

  /// YYYYMMDD → DateTime 변환. 형식 오류 시 null 반환.
  static DateTime? _parseBirthDate(String yyyymmdd) {
    try {
      if (yyyymmdd.length < 8) return null;
      final y = int.parse(yyyymmdd.substring(0, 4));
      final m = int.parse(yyyymmdd.substring(4, 6));
      final d = int.parse(yyyymmdd.substring(6, 8));
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  /// CF 오류 코드 → 사용자 메시지 변환
  static String _mapCfError(String code) {
    switch (code) {
      case 'already-exists':
        return '이미 가입된 계정이 있습니다';
      case 'permission-denied':
        return '본인인증 조건을 충족하지 않습니다 (미성년자 또는 재가입 제한)';
      case 'not-found':
        return '본인인증 세션을 찾을 수 없습니다. 다시 시도해주세요';
      case 'deadline-exceeded':
        return '본인인증 세션이 만료되었습니다. 다시 인증해주세요';
      default:
        return '본인인증에 실패했습니다. 다시 시도해주세요';
    }
  }

}
