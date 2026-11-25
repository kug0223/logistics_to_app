import 'package:flutter/material.dart';

import '../models/core/attendance_model.dart';
import '../theme/app_colors.dart';
import 'format_helper.dart';

/// [SIM-WORKER-WAGE-VIEW] 근로자에게 보이는 근무 한 건의 **지급 상태** — 한 벌.
///
///   월 근무 내역 행과 급여 상세가 이 판정을 따로 들고 있었다. 상세만
///   계좌 재확인(`wageAccountReviewRequired`)을 보고 '지급정보 확인 필요'로
///   바꿨고, 목록은 같은 건을 '지급 예정'이라고 했다(DEV 6HB9 실측).
///   노쇼로 0원이 된 근무도 급여 단계가 confirmed 라 목록에서 '지급 예정'이었다.
///
///   판정 순서:
///     transferred      → 이체 처리 완료 (기존 의미 그대로 — 관리자가 앱에서 이체 처리)
///     NO_SHOW / 결근   → 노쇼 처리됨 / 결근 처리됨 (**근태 상태**로 판정, 금액 아님)
///     confirmed        → 계좌 재확인 필요면 '지급정보 확인 필요', 아니면 '지급 예정'
///     calculated       → 급여 계산 완료
///     그 밖            → null (호출부가 근무 단계 문구를 정한다)
///
///   노쇼·결근 문구는 홈·출퇴근 화면이 이미 쓰는 것과 같다.
class WorkerWageStatus {
  WorkerWageStatus._();

  static ({String label, Color color})? of(AttendanceModel att) {
    if (att.wageStatus == AttendanceModel.wageTransferred) {
      return (label: '이체 처리 완료', color: AppColors.successDark);
    }
    if (att.status == AttendanceModel.statusNoShow) {
      return (label: '노쇼 처리됨', color: AppColors.errorDark);
    }
    if (att.status == AttendanceModel.statusAbsent) {
      // [DU596b · 판정139 §3 :44 PP-STATUS-PAIR · 판정177 §6 :60] 명시 결근 결과 = 노쇼와 같은 errorDark(홈 · 일정 카드 · 출퇴근 배너와 같은 짝).
      return (label: '결근 처리됨', color: AppColors.errorDark);
    }
    switch (att.wageStatus) {
      case AttendanceModel.wageConfirmed:
        // [PII-DOC-R1.6] 지급정보가 준비되지 않아 이체가 막힌 건을
        //   '지급 예정'이라고 말하지 않는다. 금액은 그대로 확정돼 있다.
        if (att.wageAccountReviewRequired == true) {
          return (label: '지급정보 확인 필요', color: AppColors.warning);
        }
        return (label: '지급 예정', color: AppColors.brand);
      case AttendanceModel.wageCalculated:
        return (label: '급여 계산 완료', color: AppColors.success);
      default:
        return null;
    }
  }

  /// 지급 예정일을 보여 줄 건인가 — 확정됐고 아직 이체 전이며, 노쇼·결근이 아닌 건.
  ///
  ///   이체가 끝난 건에 "예정"을 다시 말하지 않는다. 노쇼·결근은 지급할 돈이 아니다.
  static bool showsDueDate(AttendanceModel att) =>
      att.paymentDueDate != null &&
      att.wageStatus == AttendanceModel.wageConfirmed &&
      att.status != AttendanceModel.statusNoShow &&
      att.status != AttendanceModel.statusAbsent;

  /// 지급 예정일 표기 — 예: '10월 18일(일)'.
  ///
  ///   서버(`srvCalculatePaymentDueDate`)는 **KST 달력일의 UTC 자정**을 쓴다
  ///   (DEV 실측 2026-10-18T00:00Z). 그 달력일은 `toKstDate` 로 읽어도 같다
  ///   (UTC 00:00 = KST 09:00, 같은 날). 연체 판정(`PaymentDueDateCalculator`)도
  ///   같은 식으로 읽으므로 화면과 판정이 같은 날을 가리킨다.
  static String dueDateLabel(DateTime paymentDueDate) {
    const dow = ['', '월', '화', '수', '목', '금', '토', '일'];
    final d = FormatHelper.toKstDate(paymentDueDate);
    return '${d.month}월 ${d.day}일(${dow[d.weekday]})';
  }
}
