import 'package:flutter/foundation.dart';

import '../models/core/attendance_model.dart';
import 'payment_due_date_calculator.dart';

/// [PAYROLL-BANNER-DUE-SCOPE] "오늘(KST)까지 지급 예정인 미이체" — 한 벌.
///
///   급여 탭 배너는 `지급 예정일이 오늘 이하인 확정 급여 N건` 이라고 말한다.
///   예전에는 그 숫자를 (기기 로컬 23:59:59 기준) 서버 조건으로 따로 세고, 누르면
///   **지급 예정일 == 오늘** 인 날짜 화면을 열었다 — 기한이 지난 건은 거기 없어서
///   DEV 10-20 에 배너 `2건` → 화면 `0명` 이 됐다.
///
///   배너 숫자와 도착 목록은 **같은 조회 결과에 같은 조건**을 건다:
///     · 지급 대상(`isPayableForTransfer` — 확정이고, 노쇼·결근 0원이 아님)
///     · 지급 예정일이 있고, 그 KST 날짜가 오늘 KST 날짜 이하
///   지급 예정일이 없는 건·이체 완료 건·미래 예정 건은 들어가지 않는다.
///   관리자 홈의 `전체 미이체`(미래 예정 포함)는 이 조건을 쓰지 않는다.
abstract final class PayrollDueScope {
  @visibleForTesting
  static DateTime Function()? debugNow;

  /// 판정 기준 시각. 테스트는 [debugNow] 로 KST 자정 전후를 고정한다.
  static DateTime now() => debugNow?.call() ?? DateTime.now();

  static bool isDueByToday(AttendanceModel r, DateTime now) =>
      r.isPayableForTransfer &&
      PaymentDueDateCalculator.isDueOnOrBefore(r.paymentDueDate, reference: now);

  static List<AttendanceModel> dueByToday(
          Iterable<AttendanceModel> records, DateTime now) =>
      records.where((r) => isDueByToday(r, now)).toList();
}
