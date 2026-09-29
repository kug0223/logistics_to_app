import 'format_helper.dart';
import 'toast_helper.dart';

/// [CONTRACT-PERIOD-RULE] 계약 기간이 정정됐다는 **관리자 고지**.
///
/// 확정 응답의 `periodRevision` 을 사람이 읽는 한 문장으로 바꾼다.
/// 서비스 안에 문자열을 묻어 두면 화면에서 렌더해 볼 수 없어서 따로 둔다 —
/// 이 함수가 곧 테스트가 부르는 production 경로다.
///
/// 이 고지는 **관리자용**이다. 지원자에게 가는 경로는 아직 없다
/// (`docs/r7-contract-monthend-audit.md` 의 전환·고지 절 참조).
///
/// [presented] 지원자가 지원할 때 화면에서 본 종료일.
/// [applied]   확정 시 규칙으로 다시 계산한 종료일.
/// [applicantName] 누구의 지원서인지. 일괄 확정에서는 이것이 없으면
///   **어느 건이 정정됐는지 귀속되지 않는다.** 모르면 이름 자리를 비우지
///   않고 문장 자체를 바꾼다(빈 괄호·떠 있는 조사를 만들지 않는다).
String periodRevisionMessage({
  required DateTime presented,
  required DateTime applied,
  String? applicantName,
}) {
  final from = FormatHelper.formatDateISO(presented);
  final to = FormatHelper.formatDateISO(applied);
  final who = applicantName?.trim();
  final subject = (who == null || who.isEmpty)
      ? '이 지원서의 계약 종료일이'
      : '$who 님의 계약 종료일이';
  return '$subject $from → $to 로 정정되었습니다. 지원자에게 안내가 필요할 수 있습니다.';
}

/// [periodRevisionMessage] 를 관리자 화면에 띄운다.
void showPeriodRevisionNotice({
  required DateTime presented,
  required DateTime applied,
  String? applicantName,
}) {
  ToastHelper.showWarning(periodRevisionMessage(
    presented: presented,
    applied: applied,
    applicantName: applicantName,
  ));
}
