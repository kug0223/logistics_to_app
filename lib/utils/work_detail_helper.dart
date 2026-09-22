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
import '../models/core/work_detail_data.dart';

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
  /// [POSTING-V2-03I.4] 레거시 지원서도 **자기가 아는 것은 쓴다.**
  /// 스냅샷 제도 이전에도 금액·급여유형·근무시간은 지원 시점 값으로
  /// 저장돼 있었다. 완전한 스냅샷이 없다는 이유로 그 넷까지 현재 값으로
  /// 되돌리면, 공고를 고칠 때마다 과거 약속이 함께 움직인다.
  ///
  /// 레거시에 없는 조건(휴게·야간·연장 단가·공제)만 현재 값이 남는다 —
  /// **legacy compatibility 경로**다. 활성 레거시 관계가 있는 동안
  /// 그 조건이 바뀌지 않도록 막는 것은 서버 guard의 몫이다.
  /// [CROSS-DOMAIN-R5.3C.1] **약속의 부재도 약속이다.**
  ///
  /// `{...live, ...promised}`는 promised에 **키가 있을 때만** live를 덮는다.
  /// 그래서 통상시급을 자동계산에 맡긴 지원서(키 없음)는, 나중에 관리자가
  /// 공고에 통상시급을 추가하면 그 값이 빈자리로 그대로 들어왔다 —
  /// 이미 확정된 사람의 연장·야간 단가가 조용히 바뀌는 03I.2와 같은 결함이
  /// "값이 없는 경우"에만 남아 있었다.
  ///
  /// 이제 mode가 그 자리를 막는다:
  ///
  ///   MANUAL — 약속된 숫자를 쓴다.
  ///   AUTO   — live 값을 **명시적으로 지운다**. 급여 계산이 약속된 금액과
  ///            현재 근무시간으로 파생한다(기존 공식 그대로).
  ///
  /// 레거시(mode 없음)는 [ApplicationModel.baseHourlyWage]의 존재 여부로
  /// 해석한다 — canonical writer가 하나뿐이라는 invariant다. 단
  /// **스냅샷 자체가 없는** 지원서는 UNKNOWN이라 손대지 않는다: 과거 약속을
  /// 공고 현재값으로 추정하지 않고, 변경은 서버 legacy lock이 막는다.
  static Map<String, dynamic>? resolve(
    ApplicationModel app,
    Map<String, dynamic> timeMap,
  ) {
    final live = _resolveLive(app, timeMap);
    final promised = app.promisedCompensation;
    if (live == null) return promised;
    final merged = <String, dynamic>{...live, ...promised};
    if (baseHourlyWageModeOf(app) == WorkDetailData.baseHourlyAuto) {
      merged.remove('baseHourlyWage');
    }
    return merged;
  }

  /// 이 지원서의 통상시급 mode. **유일한 판정 지점.**
  ///
  /// 스냅샷이 없는 레거시는 판정하지 않고 null을 돌려준다 — 그 경우
  /// 기존 동작(공고 현재값)을 그대로 두고 서버 lock에 맡긴다.
  static String? baseHourlyWageModeOf(ApplicationModel app) {
    final stored = app.baseHourlyWageMode;
    if (stored == WorkDetailData.baseHourlyManual ||
        stored == WorkDetailData.baseHourlyAuto) {
      return stored;
    }
    if (!app.hasCompensationSnapshot) return null; // UNKNOWN — 추정하지 않는다
    return app.baseHourlyWage != null
        ? WorkDetailData.baseHourlyManual
        : WorkDetailData.baseHourlyAuto;
  }

  /// [R8-P10] 이 지원서가 timeMap 으로 풀리는가 — 로더가 추가 조회 필요 여부를
  /// 판단할 때 쓴다. 판정 기준이 한 곳에만 있어야 로더와 소비부가 갈리지 않는다.
  static Map<String, dynamic>? resolveLive(
    ApplicationModel app,
    Map<String, dynamic> timeMap,
  ) =>
      _resolveLive(app, timeMap);

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
