/// [R7-P3-2 P32-X1] 전체 사용자 화면이 **목록을 만들 때** 나가는 읽기 경계.
///
/// 외부 호출(`callableGetAllUsers`)만 잘라낸다 — 파싱·필터는 화면에 남긴다.
/// 쓰기(블랙리스트·제재 해제)는 이 경계에 넣지 않는다.
/// production 은 `reads: null` 이라 기존 CF 호출을 그대로 쓴다.
library;

import 'package:cloud_functions/cloud_functions.dart';

class AllUsersReads {
  const AllUsersReads({required this.allUsersRaw});

  /// CF 가 돌려준 `users` 원본 리스트. 파싱 전 값이다.
  final Future<List<Object?>> Function() allUsersRaw;

  factory AllUsersReads.of() => AllUsersReads(
        allUsersRaw: () async {
          final callable =
              FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                  .httpsCallable('callableGetAllUsers',
                      options: HttpsCallableOptions(
                          timeout: const Duration(seconds: 30)));
          final result = await callable.call<Map<String, dynamic>>();
          return (result.data['users'] as List?) ?? const [];
        },
      );
}
