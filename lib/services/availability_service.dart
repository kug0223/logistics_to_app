import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
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
    await _setDates(valid);
  }

  /// 근무 가능일만 비운다.
  ///
  /// [R2.3] 문서를 삭제하지 않는다 — 초대 지역 설정이 함께 사라진다.
  /// 가능일이 0일이면 어떤 날짜에도 후보로 잡히지 않으므로 효과는 같고,
  /// 다시 가능일을 등록하면 이전 초대 지역이 그대로 살아난다.
  Future<void> clearAvailability(String uid) => _setDates(const []);

  /// [SYSTEM-INTEGRATION-R2.3 CLOSURE] 단일 canonical mutation.
  ///
  ///   `dates`와 그 파생값 `inviteKeys`를 **한 번의 문서 write**로 쓴다.
  ///   예전에는 클라이언트가 dates를 직접 쓰고 나서 동기화 callable을 불렀는데,
  ///   그 둘 사이에 실패하면 가능일은 저장됐는데 후보 인덱스는 옛 날짜인
  ///   상태가 조용히 남았다. 순차 호출 두 번은 원자성이 아니다.
  ///
  ///   실패는 throw — 호출부가 사용자에게 알리고 저장되지 않았음을 보여준다.
  Future<void> _setDates(List<String> dates) async {
    await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableSetAvailability',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
        .call<Map<String, dynamic>>({'dates': dates});
  }
}
