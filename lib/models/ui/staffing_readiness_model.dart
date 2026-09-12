// lib/models/ui/staffing_readiness_model.dart
//
// callableGetStaffingReadiness 응답 DTO
//
// [설계 원칙]
//   - available: false → 쿼리 실패 (0과 "데이터 없음" 구분)
//   - shortageCount ≠ requiredCount - confirmedCount (flex는 per-wdId 합산)
//   - contract TO shortage는 totalRequired - confirmedOnDay per TO 합산
//   - pendingCount: secondary signal only — 용량 계산에 포함 금지
//   - byBusiness: 사업장별 상세 (OWNER multi-biz 시 per-business 표시용)
//
import 'package:cloud_functions/cloud_functions.dart';

/// 사업장별 날짜 인력 현황
class StaffingBizData {
  final String businessId;
  final String businessName;
  final int requiredCount;
  final int confirmedCount;
  final int shortageCount;

  /// 지원 대기 수 (secondary signal)
  ///   null  = pending 쿼리 실패 ("데이터 없음", ERROR≠ZERO)
  ///   0     = 실제 대기 없음
  ///   N > 0 = 실제 대기 N건
  final int? pendingCount;

  const StaffingBizData({
    required this.businessId,
    required this.businessName,
    required this.requiredCount,
    required this.confirmedCount,
    required this.shortageCount,
    required this.pendingCount,
  });

  factory StaffingBizData.fromMap(Map<Object?, Object?> map) {
    return StaffingBizData(
      businessId:    (map['businessId']    as String?)  ?? '',
      businessName:  (map['businessName']  as String?)  ?? '',
      requiredCount:  (map['requiredCount']  as num?)?.toInt() ?? 0,
      confirmedCount: (map['confirmedCount'] as num?)?.toInt() ?? 0,
      shortageCount:  (map['shortageCount']  as num?)?.toInt() ?? 0,
      pendingCount:   (map['pendingCount']   as num?)?.toInt(), // null = 쿼리 실패
    );
  }
}

/// 날짜 단위 인력 현황
class StaffingDayData {
  /// KST 기준 날짜 (YYYY-MM-DD)
  final String date;
  final int requiredCount;
  final int confirmedCount;

  /// 인력 부족 수 — requiredCount - confirmedCount와 다를 수 있음 (per-wdId 합산)
  final int shortageCount;

  /// 지원 대기 수 (secondary signal)
  ///   null  = pending 쿼리 실패 ("데이터 없음", ERROR≠ZERO)
  ///           → UI: "지원 대기" 텍스트 숨김
  ///   0     = 실제 대기 없음
  ///   N > 0 = 실제 대기 N건 → "지원 대기 N명"
  final int? pendingCount;

  /// 사업장별 상세 (단일 사업장이면 byBusiness.length == 1)
  final List<StaffingBizData> byBusiness;

  const StaffingDayData({
    required this.date,
    required this.requiredCount,
    required this.confirmedCount,
    required this.shortageCount,
    required this.pendingCount,
    required this.byBusiness,
  });

  factory StaffingDayData.fromMap(Map<Object?, Object?> map) {
    final rawBiz = map['byBusiness'] as List<Object?>? ?? const [];
    return StaffingDayData(
      date:           (map['date']           as String?) ?? '',
      requiredCount:  (map['requiredCount']  as num?)?.toInt() ?? 0,
      confirmedCount: (map['confirmedCount'] as num?)?.toInt() ?? 0,
      shortageCount:  (map['shortageCount']  as num?)?.toInt() ?? 0,
      pendingCount:   (map['pendingCount']   as num?)?.toInt(), // null = 쿼리 실패
      byBusiness:     rawBiz
          .whereType<Map<Object?, Object?>>()
          .map(StaffingBizData.fromMap)
          .toList(),
    );
  }
}

/// callableGetStaffingReadiness 최상위 응답 모델
class StaffingReadinessModel {
  /// 대상 사업장을 **전부** 성공적으로 조회했는지.
  ///
  /// [AH-V2-03.1] 이 필드의 의미는 구 서버와 동일하게 유지된다.
  /// partial을 모르는 구 클라이언트가 부분합을 전체 합계로 오인하지
  /// 않으려면, 부분 실패는 반드시 available=false로 보여야 하기 때문이다.
  ///
  /// 따라서 available==false만으로 ERROR를 단정하면 안 된다.
  /// 반드시 [partial]을 먼저 확인할 것.
  final bool available;

  /// 일부 사업장이 빠진 부분합인지.
  ///
  /// true면 days의 숫자는 성공한 사업장만의 합계다 — 쓸 수는 있지만
  /// 전체 합계가 아니다. UI가 이 사실을 표시해야 한다.
  ///
  /// 구 서버 응답에는 이 필드가 없어 false로 파싱되며,
  /// 그 경우 부분 실패는 기존처럼 ERROR로 나타난다 (false success 없음).
  final bool partial;

  /// 집계에서 빠진 사업장 수 (실패 건수)
  final int failedBusinessCount;

  /// D0~D+7 날짜별 인력 현황 (8일)
  final List<StaffingDayData> days;

  const StaffingReadinessModel({
    required this.available,
    required this.days,
    this.partial = false,
    this.failedBusinessCount = 0,
  });

  factory StaffingReadinessModel.empty() =>
      const StaffingReadinessModel(available: false, days: []);

  /// days를 화면에 써도 되는지 — SUCCESS 또는 PARTIAL_SUCCESS.
  ///
  /// [AH-V2-03.1] 상태 판정 순서를 여기 한 곳에만 둔다.
  ///   partial  == true  → PARTIAL_SUCCESS (부분합 표시 + notice)
  ///   available == true → SUCCESS / EMPTY
  ///   그 외              → ERROR
  ///
  /// 호출부가 available만 보고 ERROR로 빠지면 부분합을 버리게 되므로,
  /// 에러 분기는 반드시 이 getter로 판정한다.
  bool get hasUsableData => partial || available;

  /// D0(오늘)에 인력 운영 대상이 존재하는지.
  ///
  /// [AH-V2-03] 필요 인원이 0이면 그 날 모집·근무 대상 자체가 없다는 뜻이다.
  /// "대상 없음"과 "대상은 있는데 0명 부족"은 다른 상태다.
  bool get hasTodayTarget =>
      days.isNotEmpty && days.first.requiredCount > 0;

  /// D+1~D+7에 인력 운영 대상이 존재하는지.
  bool get hasFutureTarget =>
      days.skip(1).any((d) => d.requiredCount > 0);

  factory StaffingReadinessModel.fromCallable(HttpsCallableResult<dynamic> result) {
    final data = result.data;
    if (data is! Map) return StaffingReadinessModel.empty();
    final map = data as Map<Object?, Object?>;

    final available = (map['available'] as bool?) ?? false;
    final rawDays   = map['days'] as List<Object?>? ?? const [];
    final days = rawDays
        .whereType<Map<Object?, Object?>>()
        .map(StaffingDayData.fromMap)
        .toList();

    return StaffingReadinessModel(
      available: available,
      partial: (map['partial'] as bool?) ?? false,
      failedBusinessCount: (map['failedBusinessCount'] as num?)?.toInt() ?? 0,
      days: days,
    );
  }
}
