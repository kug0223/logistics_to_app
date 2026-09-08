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
  /// 쿼리 성공 여부 — false면 days 데이터가 불완전할 수 있음
  final bool available;

  /// D0~D+7 날짜별 인력 현황 (8일)
  final List<StaffingDayData> days;

  const StaffingReadinessModel({
    required this.available,
    required this.days,
  });

  factory StaffingReadinessModel.empty() =>
      const StaffingReadinessModel(available: false, days: []);

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

    return StaffingReadinessModel(available: available, days: days);
  }
}
