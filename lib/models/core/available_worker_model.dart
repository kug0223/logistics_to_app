/// Phase 8.1B — 근무 가능 인력 후보 모델
///
/// CF `callableGetAvailableWorkers` 응답 스키마.
/// 개인정보 보호: 이름 마스킹, 연락처/계좌/생년월일/주소 비포함.
///
/// [R3-C] Explainability facts (ranking 미영향):
/// - `workTypeCount`         : 해당 업무 근무 완료 횟수 (0 = 경험 없음 또는 신규)
/// - `totalWorkDays`         : ALfit 전체 근무 완료 일수 (0 = 신규 근로자)
/// - `weeklyBusinessCount`   : 이번 주 이 사업장 실제 근무 횟수 [R7.2A]
///
/// Derived:
/// - `isNewWorker`           : totalWorkDays == 0
/// - `hasSameWorkExperience` : workTypeCount > 0
///
/// 노출 금지: rankGroup / noShowCount / restrictedUntil / trustScore
/// RANKING_USES_WEEKLY_COUNT = NO
class AvailableWorkerModel {
  final String uid;

  /// 마스킹된 이름 — 예: "김○○" (서버가 마스킹하여 전달, 클라이언트 복원 불가)
  final String maskedName;

  final String city;
  final String? district;

  /// [R3-C] 해당 업무 근무 완료 횟수. 서버 구버전 응답 시 0 default.
  final int workTypeCount;

  /// [R3-C] ALfit 전체 근무 완료 일수. 서버 구버전 응답 시 0 default.
  final int totalWorkDays;

  /// [R7.2A] 이번 주 이 사업장 실제 근무 횟수.
  /// COUNT: present / late / early_leave status 기준 attendance document 단위.
  /// EXCLUDE: absent / NO_SHOW / 미래 confirmed.
  /// TARGET_BUSINESS_ONLY = YES. 서버 구버전 응답 시 0 default.
  final int weeklyBusinessCount;

  /// [SYSTEM-INTEGRATION-R2.2] 판단용 profile — 지원 검토와 같은 allowlist.
  ///
  /// 이름은 마스킹된 값으로 덮여 오고, 계좌·신분증·정확한 주소·연락처는
  /// 서버 allowlist에 없어 애초에 실리지 않는다.
  /// null = 서버 구버전 응답 (상세를 열지 않는다).
  final Map<String, dynamic>? profile;

  const AvailableWorkerModel({
    required this.uid,
    required this.maskedName,
    required this.city,
    this.district,
    this.workTypeCount = 0,
    this.totalWorkDays = 0,
    this.weeklyBusinessCount = 0,
    this.profile,
  });

  /// [R3-C] 신규 근로자 여부 — totalWorkDays == 0 으로 derive (별도 필드 불필요)
  bool get isNewWorker => totalWorkDays == 0;

  /// [R3-C] 해당 업무 경험 여부 — workTypeCount > 0 으로 derive (별도 필드 불필요)
  bool get hasSameWorkExperience => workTypeCount > 0;

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
        // [R3-C] backward-compatible: 구버전 서버 응답에 필드 없으면 0 default
        workTypeCount: (m['workTypeCount'] as num?)?.toInt() ?? 0,
        totalWorkDays: (m['totalWorkDays'] as num?)?.toInt() ?? 0,
        // [R7.2A] backward-compatible: 구버전 서버 응답에 필드 없으면 0 default
        weeklyBusinessCount: (m['weeklyBusinessCount'] as num?)?.toInt() ?? 0,
        // [R2.2] 구버전 서버 응답이면 null — 상세를 열지 않는다.
        profile: m['profile'] is Map
            ? Map<String, dynamic>.from(m['profile'] as Map)
            : null,
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
