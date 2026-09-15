import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/core/worker_availability_model.dart';

/// 근로자 근무 가능일 Firestore CRUD 서비스
///
/// 보안 설계 (Phase 8.1A):
///   · BUSINESS_ADMIN/SubAdmin direct read 금지 — Firestore Rules 에서 차단
///   · 어드민 candidate 조회는 CF callableGetAvailableWorkers (Phase 8.1C) 경유
///   · client direct write 허용 — city canonical 검증은 Rules 에서 수행
class AvailabilityService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('worker_availability');

  /// 내 근무 가능일 문서 로드.
  /// 문서 없으면 null 반환.
  Future<WorkerAvailabilityModel?> loadMyAvailability(String uid) async {
    final doc = await _col.doc(uid).get();
    return WorkerAvailabilityModel.tryFromFirestore(doc);
  }

  /// 근무 가능일 저장.
  ///
  /// [dates]: 저장할 날짜 `Set<String>` ("YYYY-MM-DD"). 유효성 필터 및 60개 cap 적용.
  /// [city]:  homeRegion.city (Rules에서 canonical 검증됨).
  /// [district]: homeRegion.district (선택).
  Future<void> saveAvailability({
    required String uid,
    required Set<String> dates,
    required String city,
    String? district,
  }) async {
    final valid = WorkerAvailabilityModel.filterValidDates(dates.toList());

    // [SYSTEM-INTEGRATION-R2.3] merge — 초대 지역 설정을 지우지 않는다.
    //   이 문서에는 CF만 쓰는 초대 필드(inviteEnabled/inviteRegionKeys/
    //   inviteKeys)가 함께 있다. 예전처럼 통째로 set하면 근무 가능일을 저장할
    //   때마다 초대 설정이 조용히 사라진다.
    await _col.doc(uid).set({
      'uid': uid,
      'dates': valid,
      'city': city,
      if (district != null && district.isNotEmpty) 'district': district,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 지역×날짜 복합 키를 서버가 다시 만든다. 클라이언트는 canonical region
    // key 규칙을 알 필요가 없고, 알아도 믿지 않는다.
    // 실패해도 근무 가능일 저장 자체는 성공이다 — 다음 설정 변경 때 복구된다.
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableSyncInviteKeys')
          .call<Map<String, dynamic>>({});
    } catch (e) {
      debugPrint('⚠️ [R2.3] 초대 지역 인덱스 동기화 실패 (가능일 저장은 완료): $e');
    }
  }

  /// 근무 가능일만 비운다.
  ///
  /// [R2.3] 문서를 삭제하지 않는다 — 초대 지역 설정이 함께 사라진다.
  /// 가능일이 0일이면 어떤 날짜에도 후보로 잡히지 않으므로 효과는 같고,
  /// 다시 가능일을 등록하면 이전 초대 지역이 그대로 살아난다.
  Future<void> clearAvailability(String uid) async {
    await _col.doc(uid).set({
      'uid': uid,
      'dates': <String>[],
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableSyncInviteKeys')
          .call<Map<String, dynamic>>({});
    } catch (e) {
      debugPrint('⚠️ [R2.3] 초대 지역 인덱스 동기화 실패: $e');
    }
  }
}
