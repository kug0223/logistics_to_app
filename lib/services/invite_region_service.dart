// [SYSTEM-INTEGRATION-R2.3] 초대 받을 지역 — 읽기/쓰기.
//
// 쓰기는 반드시 CF를 경유한다:
//   · canonical region key는 서버가 만든다 (클라이언트 값을 믿지 않는다)
//   · `ON인데 지역 0개` 같은 모순 상태를 서버가 막는다 (§8)
//   · 지역×날짜 복합 인덱스를 서버가 생성한다 (§17)
//   · 지원자 본인만 자기 설정을 바꾼다 — callable이 request.auth.uid만 쓴다 (§21)
//
// 읽기는 본인 문서 단건이라 Firestore 직접 읽기로 충분하다
// (rules: worker_availability get = 본인/SUPER_ADMIN, list = 전면 차단).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/core/invite_region_preference.dart';
import '../models/core/user_region.dart';

class InviteRegionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// 내 초대 지역 설정.
  ///
  /// 실패를 "설정 없음"으로 바꾸지 않는다 — [InvitePreferenceState.unknown].
  /// ERROR != OFF, ERROR != UNSET (§8).
  Future<InviteRegionPreference> loadMine(String uid) async {
    try {
      final doc = await _db.collection('worker_availability').doc(uid).get();
      if (!doc.exists) return const InviteRegionPreference();
      return InviteRegionPreference.fromAvailabilityMap(doc.data());
    } catch (e) {
      debugPrint('❌ [R2.3] 초대 지역 설정 조회 실패: $e');
      return const InviteRegionPreference.unknown();
    }
  }

  /// 초대 지역 설정 저장. 실패는 throw — 호출부가 사용자에게 알린다.
  ///
  /// 서버가 지역을 정규화·검증해 돌려주므로 그 결과를 그대로 반영한다.
  Future<InviteRegionPreference> save({
    required bool enabled,
    required List<UserRegion> regions,
  }) async {
    final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableSetInviteRegions',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
        .call<Map<String, dynamic>>({
      'enabled': enabled,
      'regions': regions
          .map((r) => {
                if (r.province != null) 'province': r.province,
                'city': r.city,
              })
          .toList(),
    });

    final data = result.data;
    final saved = (data['regions'] as List? ?? [])
        .map(UserRegion.tryFromMap)
        .whereType<UserRegion>()
        .toList();
    return InviteRegionPreference(
      enabled: data['enabled'] == true,
      regions: saved,
    );
  }
}
