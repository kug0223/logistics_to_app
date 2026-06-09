// lib/utils/work_detail_helper.dart
//
// workDetailTimeMap 에서 ApplicationModel 기준으로 캐시를 조회하고
// 각 필드를 안전하게 추출하는 헬퍼.
//
// workDetailId 가 있으면 그것을 우선 키로 쓰고,
// 없으면 selectedWorkType 으로 폴백한다.
// 반복되는 `detailCached is Map<String, dynamic> ? detailCached['x'] as T? ?? default : default`
// 패턴을 이 클래스로 대체한다.

import '../models/core/application_model.dart';
import '../models/core/insurance_rate_model.dart';

class WorkDetailHelper {
  /// workDetailTimeMap 에서 해당 지원자의 캐시를 조회
  ///
  /// TO 마스터(workType 단독 키)가 항상 최신값이므로 먼저 조회한다.
  /// workDetailId 복합키는 TO 마스터 키가 없을 때의 폴백이다.
  /// (TO 수정 후 슬롯 복합키는 구시간 그대로이므로 마스터를 우선해야 헤더 시간이 갱신됨)
  static Map<String, dynamic>? resolve(
    ApplicationModel app,
    Map<String, dynamic> timeMap,
  ) {
    final raw = timeMap[app.selectedWorkType]
        ?? (app.workDetailId != null ? timeMap[app.workDetailId] : null);
    return raw is Map<String, dynamic> ? raw : null;
  }

  static String?  shiftType(Map<String, dynamic>? d)             => d?['shiftType'] as String?;
  static bool     nightIncluded(Map<String, dynamic>? d)          => d?['nightIncluded'] as bool? ?? false;
  static bool     nightAllowanceApplied(Map<String, dynamic>? d)  => d?['nightAllowanceApplied'] as bool? ?? true;
  static int      breakMinutes(Map<String, dynamic>? d)           => d?['breakMinutes'] as int? ?? 0;
  static String   wageType(Map<String, dynamic>? d)               => d?['wageType'] as String? ?? 'hourly';
  static int?     baseHourlyWage(Map<String, dynamic>? d)         => d?['baseHourlyWage'] as int?;
  static int      wage(Map<String, dynamic>? d)                   => d?['wage'] as int? ?? 0;
  static String   taxDeductionType(Map<String, dynamic>? d)       => d?['taxDeductionType'] as String? ?? InsuranceRateModel.typeNone;

  /// timeMap에서 실제 출근 예정 시각 반환 (캐시 우선 → app.startTime → '09:00')
  static String effectiveStart(ApplicationModel app, Map<String, dynamic> timeMap) {
    final t = resolve(app, timeMap)?['startTime'] as String? ?? '';
    return t.isNotEmpty ? t : (app.startTime.isNotEmpty ? app.startTime : '09:00');
  }

  /// timeMap에서 실제 퇴근 예정 시각 반환 (캐시 우선 → app.endTime → '18:00')
  static String effectiveEnd(ApplicationModel app, Map<String, dynamic> timeMap) {
    final t = resolve(app, timeMap)?['endTime'] as String? ?? '';
    return t.isNotEmpty ? t : (app.endTime.isNotEmpty ? app.endTime : '18:00');
  }
}
