// lib/screens/legal/legal_consent_reads.dart
//
// [R7-LEGAL.1B.1] 재동의 화면이 바깥과 주고받는 경계.
//
//   이 화면은 법적 동의를 만든다. "무엇을 보여 주고 무엇을 보냈는가" 가
//   실행으로 확인돼야 하므로 읽기·기록을 한 겹 분리한다(1A 와 같은 이유).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/core/legal_readiness.dart';
import '../../models/core/legal_terms_model.dart';
import '../../services/legal_terms_service.dart';

class LegalConsentReads {
  const LegalConsentReads({
    required this.readiness,
    required this.terms,
    required this.storedConsent,
    required this.recordConsent,
  });

  /// 서버 판정. 실패는 throw — 호출자가 ERROR 로 그린다.
  final Future<LegalReadiness> Function() readiness;

  /// [R7-PAYROLL-POLICY.5B] 서버가 판정한 **시행 중** 약관. 실패는 throw —
  /// 화면이 ERROR 로 그린다. 기본값으로 대체하지 않는다.
  final Future<EffectiveLegalTerms> Function() terms;

  /// `users/{uid}.termsConsent` 원본.
  final Future<Map<String, dynamic>> Function() storedConsent;

  /// 동의 기록. 실패는 throw — 성공으로 바꾸지 않는다.
  final Future<void> Function(Map<String, dynamic> consentRecord) recordConsent;

  factory LegalConsentReads.of() {
    final fns = FirebaseFunctions.instanceFor(region: 'asia-northeast3');
    return LegalConsentReads(
      readiness: () async {
        final res = await fns
            .httpsCallable('callableGetLegalReadiness',
                options:
                    HttpsCallableOptions(timeout: const Duration(seconds: 15)))
            .call<Map<dynamic, dynamic>>();
        return LegalReadiness.fromServer(res.data);
      },
      terms: LegalTermsService().fetchEffectiveTerms,
      storedConsent: () async {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) return <String, dynamic>{};
        final snap =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final raw = snap.data()?['termsConsent'];
        return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      },
      recordConsent: (record) async {
        await fns
            .httpsCallable('callableRecordTermsConsent',
                options:
                    HttpsCallableOptions(timeout: const Duration(seconds: 15)))
            .call({'consentRecord': record, 'source': 'reconsent'});
      },
    );
  }
}
