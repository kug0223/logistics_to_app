import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../utils/identity_identifier.dart';

/// [PII-B4-R1.4] 근로자 본인의 세무 identity 등록.
///
///   ── 이 서비스가 절대 하지 않는 것 ──────────────────────────
///
///   등록된 번호를 **되받지 않는다.** 서버는 어떤 응답에도 식별번호를
///   싣지 않고, 화면은 "등록 완료"까지만 말한다. 그래서 한 번 등록한
///   뒤에는 앱 어디에서도 그 번호를 다시 볼 수 없다.
///
///   ── 대조는 왜 여기서만 가능한가 ────────────────────────────
///
///   전체 13자리를 손에 쥐는 순간은 근로자가 **입력하는 그때**뿐이다.
///   그래서 신분증 대조도 그 자리에서 하고, 결과는 판정 어휘로만
///   서버에 간다. 번호는 가지 않는다.
///
///   ── OCR은 권한이 아니다 ────────────────────────────────────
///
///   등록의 가부는 서버가 정한다 — 형식·본인인증 정보 일치·검증부호.
///   여기서 보내는 대조 결과는 "확인이 필요한가"를 말할 뿐이다.
class TaxIdentityService {
  TaxIdentityService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// [§14] 수집 활성화 플래그. **기본값 false** — fetch 실패가 곧
  ///   무단 수집이 되지 않게 한다. 서버도 같은 스위치를 따로 갖고 있고,
  ///   보안 경계는 그쪽이다(이건 화면을 감출 뿐이다).
  static const String remoteConfigKey = 'tax_identity_collection_enabled';

  static bool get collectionEnabledLocally {
    try {
      return FirebaseRemoteConfig.instance.getBool(remoteConfigKey);
    } catch (_) {
      return false;
    }
  }

  /// 본인 등록 상태. 번호는 포함되지 않는다.
  static Future<TaxIdentityStatus> loadStatus() async {
    try {
      final res = await _fn.httpsCallable('callableGetTaxIdentityStatus').call();
      final m = Map<String, dynamic>.from(res.data as Map);
      return TaxIdentityStatus(
        registered: m['registered'] == true,
        identifierType: m['identifierType'] as String?,
        collectionEnabled: m['collectionEnabled'] == true,
        foreignRecoveryAvailable: m['foreignRecoveryAvailable'] == true,
        documentMatch: docFieldOutcomeFromWire(m['documentMatch']),
        documentMatchCurrent: m['documentMatchCurrent'] == true,
        loadFailed: false,
      );
    } catch (e) {
      // 실패를 "미등록"으로 바꾸지 않는다 — 모르는 것은 모른다고 한다.
      debugPrint('⚠️ [TaxIdentity] 상태 조회 실패: ${e.runtimeType}');
      return const TaxIdentityStatus.unknown();
    }
  }

  /// 최초 등록. [documentMatch]는 입력 시점의 신분증 대조 결과.
  ///
  /// 성공 시 null, 실패 시 사용자에게 보여줄 문구.
  static Future<String?> register(
    String rawIdentifier, {
    DocFieldOutcome documentMatch = DocFieldOutcome.unassessed,
  }) =>
      _submit('callableRegisterTaxIdentity', rawIdentifier, documentMatch);

  /// 본인 정정. 지문이 바뀌면 모든 사업장의 확인이 낡는다.
  static Future<String?> update(
    String rawIdentifier, {
    DocFieldOutcome documentMatch = DocFieldOutcome.unassessed,
  }) =>
      _submit('callableUpdateTaxIdentity', rawIdentifier, documentMatch);

  /// [PII-B4-R1.4.1 §13] 수집이 꺼져 있을 때 가입한 외국인의 복구.
  ///
  ///   일반 등록이 아니다. 서버가 입력값을 **가입 때 만든 신원 지문과
  ///   대조**해서 같을 때만 받는다. 다르면 아무것도 쓰지 않는다 —
  ///   번호가 바뀐 것이라면 신원 재확인의 일이지 세무정보 정정이 아니다.
  static Future<String?> recoverForeign(String rawForeignIdentifier) async {
    try {
      await _fn.httpsCallable('callableRecoverForeignTaxIdentity')
          .call({'rawForeignIdentifier': rawForeignIdentifier});
      return null;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ [TaxIdentity] 외국인 복구 실패 | code=${e.code}');
      return e.message ?? '세무정보를 저장하지 못했습니다.';
    } catch (e) {
      debugPrint('❌ [TaxIdentity] 외국인 복구 실패: ${e.runtimeType}');
      return '세무정보를 저장하지 못했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  static Future<String?> _submit(
    String name,
    String rawIdentifier,
    DocFieldOutcome documentMatch,
  ) async {
    try {
      await _fn.httpsCallable(name).call({
        'rawIdentifier': rawIdentifier,
        'documentMatch': documentMatch.wire,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      // 서버 문구를 그대로 쓴다 — 어디가 틀렸는지 아는 쪽이 서버다.
      debugPrint('❌ [TaxIdentity] $name 실패 | code=${e.code}');
      return e.message ?? '세무정보를 저장하지 못했습니다.';
    } catch (e) {
      debugPrint('❌ [TaxIdentity] $name 실패: ${e.runtimeType}');
      return '세무정보를 저장하지 못했습니다. 잠시 후 다시 시도해주세요.';
    }
  }
}

/// 본인이 볼 수 있는 세무 identity 상태 — 번호 없음.
class TaxIdentityStatus {
  const TaxIdentityStatus({
    required this.registered,
    required this.identifierType,
    required this.collectionEnabled,
    required this.documentMatch,
    required this.documentMatchCurrent,
    required this.loadFailed,
    this.foreignRecoveryAvailable = false,
  });

  /// 조회 자체가 실패했을 때. `registered == false`와 **다르다**.
  const TaxIdentityStatus.unknown()
      : registered = false,
        identifierType = null,
        collectionEnabled = false,
        foreignRecoveryAvailable = false,
        documentMatch = DocFieldOutcome.unassessed,
        documentMatchCurrent = false,
        loadFailed = true;

  final bool registered;
  final String? identifierType;
  final bool collectionEnabled;

  /// [§12] 외국인 신원은 있는데 세무 레코드가 없다 — 복구 CTA 대상.
  ///   정상 가입한 외국인은 이 값이 false다(이미 등록돼 있으므로).
  final bool foreignRecoveryAvailable;

  /// 입력 시점에 신분증과 대조한 결과.
  final DocFieldOutcome documentMatch;

  /// 그 대조가 **지금 신분증**에 대한 것인가.
  final bool documentMatchCurrent;

  final bool loadFailed;

  bool get isForeign => identifierType == 'FOREIGN_REGISTRATION_NUMBER';

  /// [§35] 지원을 막는 명시적 불일치인가.
  bool get blocksApply =>
      registered &&
      documentMatchCurrent &&
      documentMatch == DocFieldOutcome.mismatch;

  /// 화면에 쓸 상태 문구. "인증 완료" 계열 표현은 쓰지 않는다.
  String get label {
    if (loadFailed) return '확인 불가';
    if (!registered) return '미등록';
    if (blocksApply) return '정보 확인 필요';
    return '등록 완료';
  }
}
