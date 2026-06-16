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
  /// 'HH:mm:ss' → 'HH:mm' 정규화 (레거시 Firestore 데이터 대응)
  static String _normalizeTime(String t) =>
      t.length >= 5 ? t.substring(0, 5) : t;

  /// workDetailTimeMap 에서 해당 지원자의 캐시를 조회
  ///
  /// 우선순위:
  /// 1. workType_startTime_endTime 복합키 (app.startTime/endTime 기반) — 가장 정확
  /// 2. workDetailId 복합키 (슬롯 ID 기반 레거시)
  /// 3. selectedWorkType 단독 키 — 같은 workType 이름의 다른 시간대 업무가 있을 때 오반환 위험
  static Map<String, dynamic>? resolve(
    ApplicationModel app,
    Map<String, dynamic> timeMap,
  ) {
    // 1. startTime/endTime 복합키 우선 (동일 workType 다중 시간대 오반환 방지)
    if (app.startTime.isNotEmpty) {
      final compositeKey =
          '${app.selectedWorkType}_${_normalizeTime(app.startTime)}_${_normalizeTime(app.endTime)}';
      final byComposite = timeMap[compositeKey];
      if (byComposite is Map<String, dynamic>) return byComposite;
    }
    // 2. workDetailId 복합키
    if (app.workDetailId != null && app.workDetailId!.isNotEmpty) {
      final byId = timeMap[app.workDetailId];
      if (byId is Map<String, dynamic>) return byId;
    }
    // 3. workType 단독 키 폴백
    final raw = timeMap[app.selectedWorkType];
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
