// [LATE-RENEW-EFFECTIVE-DATE-POLICY]
//
// Post-expiry renewal must use an explicit effective date.
// Core V1 ordinary renewal does not silently infer retroactive D+1
// continuity.
//
// This is a product-safety rule, not a legal determination that
// employment continuity is broken by a calendar gap.
//
// ─────────────────────────────────────────────────────────────────
//
// 무엇이 문제였나.
//
//   OLD 종료일 = 9/20
//   오늘       = 9/26
//   관리자가 연장 버튼을 누름
//
//   → NEW 시작일 = 9/21
//
// 그런데 9/21~9/25 에는 실제로 근무 자격도, 근태도, 결근 의무도,
// 좌석도 없었다. 나중에 버튼을 눌렀다는 이유로 시스템이 그 기간을
// 새 계약기간으로 **조용히** 만들어서는 안 된다.
//
// 그리고 그 어긋남은 눈에 띄지도 않았다. 세 곳이 서로 다른 말을 하되
// 한 곳이 다른 곳을 덮고 있었기 때문이다:
//
//   Application.workDate     = 9/21
//   Contract.contractStart   = 9/21
//   근무 가능 시작(eligibility) = 9/26   ← confirmedAt 보정이 조용히 당김
//
// 그래서 이 Phase 는 **명시적 효력일**을 저장한다. 세 값이 처음부터
// 같은 날을 말하면 덮을 것이 없다.
//
// ─────────────────────────────────────────────────────────────────
//
// 왜 과거 날짜를 막는가 (Core V1).
//
// 과거 효력일이 법적으로 불가능하다는 판단이 **아니다**. ALfit V1 에
// 아직 다음이 없기 때문에 택한 제품 운영 제한이다:
//
//   과거 실제근무 reconciliation · 과거 attendance 보정 ·
//   과거 NO_SHOW 제거 · 과거 임금 재산정 · 소급 계약 정정 감사기록
//
// 실제로 공백 기간에 근무한 사실이 있었다면 그것은 "계약 연장"이
// 아니라 historical reconciliation 문제이고, 별도 설계 대상이다.

import '../models/core/application_model.dart';
import 'format_helper.dart';

/// 연장으로 만들 새 계약의 기간.
class RenewalPeriod {
  /// 새 계약 효력 시작일 (KST 달력일 비교 키).
  final DateTime start;

  /// 새 계약 종료일 (inclusive, KST 달력일 비교 키).
  final DateTime end;

  /// 원본 계약에서 승계한 개월 수. 기간 정책은 새로 만들지 않는다.
  final int months;

  /// 이미 만료된 뒤의 연장인가 — 그렇다면 시작일은 명시적으로 고른 값이다.
  final bool isLate;

  const RenewalPeriod({
    required this.start,
    required this.end,
    required this.months,
    required this.isLate,
  });
}

/// 오늘이 원본 계약 종료일을 지났는가.
///
/// 종료일 D 는 **마지막 근무 가능일**이다. today == D 는 아직 만료가
/// 아니다 — D+1 은 여전히 미래이므로 기존 연속 연장 UX 그대로다.
bool isLateRenewal(ApplicationModel app, DateTime today) {
  final end = app.actualResignDate ?? app.workEndDate;
  if (end == null) return false;
  return FormatHelper.toKstDate(today).isAfter(FormatHelper.toKstDate(end));
}

/// 고를 수 있는 가장 이른 새 계약 시작일.
///
///   만료 전 : D+1  (아직 미래 — silent retroactivity 가 아니다)
///   만료 후 : 오늘 (과거는 고를 수 없다)
///
/// 두 경우 모두 서버의 `newStart > OLD effectiveEnd` 보장을 깨지 않는다.
DateTime earliestRenewalStart(ApplicationModel app, DateTime today) {
  final end = app.actualResignDate ?? app.workEndDate;
  final todayKst = FormatHelper.toKstDate(today);
  if (end == null) return todayKst;
  final dayAfterEnd = FormatHelper.toKstDate(end).add(const Duration(days: 1));
  return dayAfterEnd.isAfter(todayKst) ? dayAfterEnd : todayKst;
}

/// 원본 계약에서 승계하는 개월 수.
///
/// 기존 계산을 그대로 옮긴 것이다 — 이 Phase 는 기간 정책을 바꾸지 않는다.
int renewalMonthsOf(ApplicationModel app) {
  final end = app.actualResignDate ?? app.workEndDate;
  if (end == null) return 1;
  final originalStart = app.desiredStartDate ?? app.workDate;
  final months = (end.year - originalStart.year) * 12 +
      (end.month - originalStart.month);
  return months > 0 ? months : 1;
}

/// 시작일 [start] 로 시작하는 연장 계약의 기간.
///
/// 종료일은 **시작일 기준**으로 계산한다. 예전에는 언제 누르든 원본
/// 종료일에 개월 수를 더했다 — 만료 뒤에 누르면 그만큼 계약이 짧아졌다.
///
/// 만료 전(`start == D+1`)에는 `start - 1 == D` 이므로 결과가 예전과
/// 완전히 같다. 일반화이지 정책 변경이 아니다.
RenewalPeriod renewalPeriodFrom(
  ApplicationModel app,
  DateTime start, {
  required bool isLate,
}) {
  final months = renewalMonthsOf(app);
  final anchor =
      FormatHelper.toKstDate(start).subtract(const Duration(days: 1));
  final rawYear = anchor.year + ((anchor.month + months - 1) ~/ 12);
  final rawMonth = (anchor.month + months - 1) % 12 + 1;
  final lastDayOfMonth = DateTime.utc(rawYear, rawMonth + 1, 0).day;
  final end = DateTime.utc(
    rawYear,
    rawMonth,
    anchor.day.clamp(1, lastDayOfMonth),
  );
  return RenewalPeriod(
    start: FormatHelper.toKstDate(start),
    end: end,
    months: months,
    isLate: isLate,
  );
}

/// 이 지원서를 [today] 에 연장한다면 기본으로 제안할 기간.
///
///   만료 전 → 시작 D+1   (확인만 받으면 된다)
///   만료 후 → 시작 오늘  (관리자가 날짜를 **명시적으로** 확인·변경한다)
RenewalPeriod defaultRenewalPeriod(ApplicationModel app, DateTime today) =>
    renewalPeriodFrom(
      app,
      earliestRenewalStart(app, today),
      isLate: isLateRenewal(app, today),
    );
