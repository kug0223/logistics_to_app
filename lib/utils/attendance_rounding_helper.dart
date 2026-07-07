import 'package:flutter/foundation.dart';

import '../models/core/business_model.dart';

/// 출퇴근 펀치 유형
enum RoundingType {
  /// 정시 출근 (earlyWindow 이내 조기 도착 포함)
  onTime,
  /// 조출 — 정규 시작 전 earlyWindow 초과 조기 도착
  earlyArrival,
  /// 지각 유예 — lateGrace 이내 늦은 도착
  lateGrace,
  /// 지각 — lateGrace 초과
  late,
  /// 정시 퇴근 (lateWindow 이내)
  onTimeOut,
  /// 조퇴 — contractEnd 전 퇴근
  earlyLeave,
  /// 연장 — contractEnd 후 퇴근
  overtime,
}

/// 반올림 처리 결과 (펀치 1회 분)
class RoundingResult {
  /// contractRef 기준 부호 있는 오프셋(분)
  /// - processCheckin : contractStart 기준 (음수=조출, 양수=지각)
  /// - processCheckout: contractEnd   기준 (음수=조퇴, 양수=연장)
  final int roundedOffset;

  /// 반올림 후 실제 DateTime (referenceAt + Duration(minutes: roundedOffset))
  final DateTime roundedAt;

  /// 표시용 "HH:mm" 문자열
  final String rounded;

  /// 펀치 유형
  final RoundingType type;

  /// 설명 (관리자 피드백 · 감사 로그용)
  final String description;

  const RoundingResult({
    required this.roundedOffset,
    required this.roundedAt,
    required this.rounded,
    required this.type,
    required this.description,
  });
}

// ── 내부 유틸 ─────────────────────────────────────────────────

String _fmt(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

RoundingResult _make(
  DateTime referenceAt,
  int roundedOffset,
  RoundingType type,
  String description,
) {
  final dt = referenceAt.add(Duration(minutes: roundedOffset));
  return RoundingResult(
    roundedOffset: roundedOffset,
    roundedAt: dt,
    rounded: _fmt(dt),
    type: type,
    description: description,
  );
}

// ── 공개 유틸 — 계약 기준 DateTime 계산 ──────────────────────

/// [workDate] + "HH:mm" 문자열 → 계약 출근 DateTime
DateTime contractStartAt(DateTime workDate, String startTimeHHmm) {
  final p = startTimeHHmm.split(':');
  return DateTime(
    workDate.year, workDate.month, workDate.day,
    int.parse(p[0]), int.parse(p[1]),
  );
}

/// [workDate] + start/end "HH:mm" → 계약 퇴근 DateTime
///
/// end < start 이면 +1일 적용 (야간 교대, 00:00 종료 등 자동 처리)
/// end == start(데이터 오류)는 0분 근무로 유지 — 24시간 시프트로 오해석 방지
DateTime contractEndAt(
    DateTime workDate, String startTimeHHmm, String endTimeHHmm) {
  final start = contractStartAt(workDate, startTimeHHmm);
  var end     = contractStartAt(workDate, endTimeHHmm);
  if (end.isBefore(start)) end = end.add(const Duration(days: 1));
  return end;
}

// ── 공개 API ──────────────────────────────────────────────────

/// 출근 펀치에 [rules] 를 적용해 반올림 결과를 반환한다.
///
/// [offsetMinutes] = `punchAt.difference(contractStartAt(...)).inMinutes`
///   음수 → 계약 출근 전 도착 (조출 / 정시 유예)
///   양수 → 계약 출근 후 도착 (정시 유예 / 지각)
///
/// [referenceAt] = `contractStartAt(...)` — roundedAt 산출 기준
RoundingResult processCheckin({
  required int offsetMinutes,
  required DateTime referenceAt,
  required AttendanceRules rules,
}) {
  // ── 조출 (earlyWindow 초과) — ceil toward contractStart ───
  // Dart ~/ 는 zero-truncation: 음수 오프셋에서 0 방향 = contractStart 방향
  if (offsetMinutes < -rules.earlyWindow) {
    final rounded =
        (offsetMinutes ~/ rules.earlyArrivalUnit) * rules.earlyArrivalUnit;
    return _make(referenceAt, rounded, RoundingType.earlyArrival,
        '조출 ${-offsetMinutes}분 → ${_fmt(referenceAt.add(Duration(minutes: rounded)))} 처리');
  }

  // ── 정시 출근 (earlyWindow 이내 · lateGrace 이내) ─────────
  if (offsetMinutes <= rules.lateGrace) {
    return _make(
      referenceAt,
      0,
      offsetMinutes <= 0 ? RoundingType.onTime : RoundingType.lateGrace,
      offsetMinutes <= 0
          ? '정시 출근'
          : '지각 유예 $offsetMinutes분 → 정시 처리',
    );
  }

  // ── 지각 (ceil: 보수적 방향) ──────────────────────────────
  final rounded =
      ((offsetMinutes + rules.lateUnit - 1) ~/ rules.lateUnit) * rules.lateUnit;
  return _make(referenceAt, rounded, RoundingType.late,
      '지각 $offsetMinutes분 → $rounded분 처리');
}

/// 퇴근 펀치에 [rules] 를 적용해 반올림 결과를 반환한다.
///
/// [offsetMinutes] = `punchAt.difference(contractEndAt(...)).inMinutes`
///   음수 → 계약 퇴근 전 퇴근 (조퇴)
///   양수 → 계약 퇴근 후 퇴근 (정시 유예 / 연장)
///
/// [referenceAt] = `contractEndAt(...)` — roundedAt 산출 기준
RoundingResult processCheckout({
  required int offsetMinutes,
  required DateTime referenceAt,
  required AttendanceRules rules,
}) {
  // ── 연장 (lateWindow 초과) — floor toward contractEnd ─────
  if (offsetMinutes > rules.lateWindow) {
    final rounded =
        (offsetMinutes ~/ rules.overtimeUnit) * rules.overtimeUnit;
    return _make(referenceAt, rounded, RoundingType.overtime,
        '연장 $offsetMinutes분 → $rounded분 처리');
  }

  // ── 정시 퇴근 (lateWindow 이내 초과 포함) ─────────────────
  if (offsetMinutes >= 0) {
    return _make(referenceAt, 0, RoundingType.onTimeOut,
        '정시 퇴근 ($offsetMinutes분 초과 → lateWindow 내 정시 처리)');
  }

  // ── 조퇴 (floor toward -∞: ceil of |offset|) ─────────────
  // earlyDiff = -offsetMinutes (양수)
  // floor의 퇴근 시각 = contractEnd - ceil(earlyDiff/unit)*unit
  final earlyDiff = -offsetMinutes;
  final rounded   = -(((earlyDiff + rules.earlyLeaveUnit - 1) ~/
                        rules.earlyLeaveUnit) *
                       rules.earlyLeaveUnit);
  return _make(referenceAt, rounded, RoundingType.earlyLeave,
      '조퇴 $earlyDiff분 전 → ${_fmt(referenceAt.add(Duration(minutes: rounded)))} 처리');
}

/// null 이면 [AttendanceRules.defaults()] 로 폴백
AttendanceRules resolveRules(AttendanceRules? rules) =>
    rules ?? AttendanceRules.defaults();

/// 디버그 전용 — 규칙 적용 결과 로그
void debugLogRounding({
  required String label,
  required DateTime punchAt,
  required RoundingResult result,
}) {
  debugPrint(
    '[AttendanceRounding] $label punch=${_fmt(punchAt)} '
    '→ rounded=${result.rounded} (${result.type.name}) ${result.description}',
  );
}
