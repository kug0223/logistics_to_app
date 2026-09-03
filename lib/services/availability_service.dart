import 'package:cloud_firestore/cloud_firestore.dart';
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

    await _col.doc(uid).set({
      'uid': uid,
      'dates': valid,
      'city': city,
      if (district != null && district.isNotEmpty) 'district': district,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 근무 가능일 전체 삭제.
  Future<void> clearAvailability(String uid) async {
    await _col.doc(uid).delete();
  }
}
