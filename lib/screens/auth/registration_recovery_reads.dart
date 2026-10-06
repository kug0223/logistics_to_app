// lib/screens/auth/registration_recovery_reads.dart
//
// [LEGAL-1A] 복구 화면이 바깥과 주고받는 경계.
//
// 이 화면은 법적 동의를 만든다. 그래서 "무엇을 보여 주고, 무엇을 보냈는가"가
// 실행으로 확인돼야 한다 — Firestore·Functions 를 직접 잡고 있으면 그 확인을
// 할 수가 없다. 읽기와 기록을 한 겹 분리한다.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/core/legal_terms_model.dart';
import '../../services/legal_terms_service.dart';

class RegistrationRecoveryReads {
  const RegistrationRecoveryReads({
    required this.currentUid,
    required this.userDoc,
    required this.terms,
    required this.recordConsent,
  });

  /// 지금 로그인한 Auth 계정. pending 계정은 `UserProvider.currentUser` 가
  /// null 이라 provider 에서 가져올 수 없다.
  final String? Function() currentUid;

  /// `users/{uid}` 원본. 문서가 없으면 null — 못 읽은 것과 구별하기 위해
  /// 실패는 throw 로 알린다.
  final Future<Map<String, dynamic>?> Function(String uid) userDoc;

  final Future<LegalTerms> Function() terms;

  /// 동의 기록. 실패는 throw — 호출자가 성공으로 바꾸지 않는다.
  final Future<void> Function(Map<String, dynamic> consentRecord) recordConsent;

  factory RegistrationRecoveryReads.of() {
    final db = FirebaseFirestore.instance;
    final service = LegalTermsService();
    return RegistrationRecoveryReads(
      currentUid: () => FirebaseAuth.instance.currentUser?.uid,
      userDoc: (uid) async {
        final snap = await db.collection('users').doc(uid).get();
        return snap.exists ? snap.data() : null;
      },
      terms: service.getTerms,
      recordConsent: (record) async {
        await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableRecordTermsConsent',
                options:
                    HttpsCallableOptions(timeout: const Duration(seconds: 15)))
            .call({'consentRecord': record});
      },
    );
  }
}
