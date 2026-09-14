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
  /// [POSTING-V2-03I.3] 급여 산정 조건은 **지원 시점 약속**이 우선한다.
  ///
  /// [timeMap]은 공고의 **현재** 조건이다. 급여를 확정할 때 그것을 읽으면,
  /// 그 사이 관리자가 휴게시간·야간 설정·연장 단가를 바꾼 것이 이미 확정된
  /// 근무자에게 소급 적용된다. 금액(wage)만 스냅샷으로 막고 나머지를 현재
  /// 값에서 읽던 것이 03I.2에서 드러난 문제였다.
  ///
  /// 그래서 약속 스냅샷을 현재 값 **위에 덮는다**. 업무 아이콘·shiftType처럼
  /// 스냅샷에 없는 표시 정보는 현재 값이 그대로 남는다.
  ///
  /// 스냅샷이 없는 레거시 지원서는 예전처럼 현재 값을 쓴다 —
  /// **legacy compatibility 경로**이며, 신규 지원서는 여기에 오지 않는다.
  static Map<String, dynamic>? resolve(
    ApplicationModel app,
    Map<String, dynamic> timeMap,
  ) {
    final live = _resolveLive(app, timeMap);
    final promised = app.compensationSnapshot;
    if (promised == null) return live; // legacy compatibility
    if (live == null) return promised;
    return {...live, ...promised};
  }

  /// 공고의 현재 조건만 조회 (약속 스냅샷 미반영).
  static Map<String, dynamic>? _resolveLive(
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
  static int      breakMinutes(Map<String, dynamic>? d)           => (d?['breakMinutes'] as num?)?.toInt() ?? 0;
  static String   wageType(Map<String, dynamic>? d)               => d?['wageType'] as String? ?? 'hourly';
  static int?     baseHourlyWage(Map<String, dynamic>? d)         => (d?['baseHourlyWage'] as num?)?.toInt();
  static int      wage(Map<String, dynamic>? d)                   => (d?['wage'] as num?)?.toInt() ?? 0;
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
