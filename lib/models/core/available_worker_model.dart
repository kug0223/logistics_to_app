/// Phase 8.1B — 근무 가능 인력 후보 모델
///
/// CF `callableGetAvailableWorkers` 응답 스키마.
/// 개인정보 보호: 이름 마스킹, 연락처/계좌/생년월일/주소 비포함.
class AvailableWorkerModel {
  final String uid;

  /// 마스킹된 이름 — 예: "김○○" (서버가 마스킹하여 전달, 클라이언트 복원 불가)
  final String maskedName;

  final String city;
  final String? district;

  const AvailableWorkerModel({
    required this.uid,
    required this.maskedName,
    required this.city,
    this.district,
  });

  static AvailableWorkerModel? tryFromMap(Object? raw) {
    if (raw == null) return null;
    try {
      final m = Map<String, dynamic>.from(raw as Map);
      final uid = m['uid'] as String?;
      if (uid == null || uid.isEmpty) return null;
      return AvailableWorkerModel(
        uid: uid,
        maskedName: m['maskedName'] as String? ?? '○○○',
        city: m['city'] as String? ?? '',
        district: m['district'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  static List<AvailableWorkerModel> listFromResponse(List<dynamic>? raw) {
    if (raw == null) return [];
    return raw
        .map((e) => AvailableWorkerModel.tryFromMap(e))
        .whereType<AvailableWorkerModel>()
        .toList();
  }

  /// 지역 표시 — "서울 강남구" or "서울"
  String get locationLabel =>
      district != null && district!.isNotEmpty ? '$city $district' : city;
}
