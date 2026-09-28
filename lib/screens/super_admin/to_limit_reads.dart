/// [R7-P3-2 P32-X2] TO 한도 설정 화면이 **값을 읽을 때** 나가는 두 경계.
///
/// 전역 기본값(`settings/app_config`)과 관리자 목록(`callableGetBusinessAdmins`)뿐이다.
/// 저장(`maxActiveTOPerBusiness` 쓰기 · `callableSetAdminTOLimit`)은 **넣지 않는다** —
/// 읽기 경계에 쓰기를 섞지 않는다.
/// production 은 `reads: null` 이라 기존 호출을 그대로 쓴다.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ToLimitReads {
  const ToLimitReads({
    required this.globalConfigRaw,
    required this.businessAdminsRaw,
  });

  /// `settings/app_config` 문서 원본. 문서가 없으면 null.
  final Future<Map<String, dynamic>?> Function() globalConfigRaw;

  /// CF 가 돌려준 `admins` 원본 리스트. 파싱 전 값이다.
  final Future<List<Object?>> Function() businessAdminsRaw;

  factory ToLimitReads.of() => ToLimitReads(
        globalConfigRaw: () async {
          final doc = await FirebaseFirestore.instance
              .collection('settings')
              .doc('app_config')
              .get();
          return doc.data();
        },
        businessAdminsRaw: () async {
          final callable =
              FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                  .httpsCallable('callableGetBusinessAdmins',
                      options: HttpsCallableOptions(
                          timeout: const Duration(seconds: 30)));
          final result = await callable.call<Map<String, dynamic>>({});
          return (result.data['admins'] as List?) ?? const [];
        },
      );
}
