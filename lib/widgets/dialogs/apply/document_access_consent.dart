import 'package:flutter/material.dart';

import '../styled_dialog.dart';

/// 서류 접근 사전동의 고지 — 문구와 버전의 단일 소유자.
///
/// [DS-08B.5] 지원서에 기록되는 `documentAccessConsentVersion`은
/// "사용자가 실제로 본 문구의 버전"이어야 한다. 문구와 버전이 서로
/// 다른 파일에 흩어지면 한쪽만 고쳤을 때 기록이 거짓이 된다.
/// 그래서 둘을 여기 한 곳에 둔다 — 문구를 고치면 버전도 같이 올린다.
///
/// 지원 요청을 보내는 경로는 반드시 이 카드를 표시한 뒤 [version]을 전송한다.
///
/// [LEGAL-REVIEW-ID-CONSENT] 동의 문구 및 방식의 법적 적절성은 별도 법무 검토 필요.
class DocumentAccessConsent {
  const DocumentAccessConsent._();

  /// 아래 [copyFor] 문안의 버전. 서버 allowlist와 일치해야 한다.
  ///
  /// 버전 이력
  ///   "2026-08-v1"     신분증만 언급 (구 문구)
  ///   "2026-08-21-v1"  신분증(확정일+7일) + 급여계좌·통장사본 명시
  ///   "2026-09-12-v2"  신분증 종료 기준을 마지막 근무일+7일로 변경
  ///                    + 계약 갱신 승계 명시
  static const String version = '2026-09-12-v2';

  static String copyFor(String businessName) =>
      '지원하기를 누르면 [$businessName]의 권한 있는 관리자가 '
      '근무 확정 시 소득신고·급여처리 목적으로 등록된 서류에 접근할 수 있음에 동의합니다.\n'
      '· 신분증: 근무 확정 시 열람 권한이 활성화되며, '
      '해당 근무관계의 마지막 근무일로부터 7일 후 자동 종료됩니다.\n'
      '· 급여계좌·통장사본: 급여처리 관계가 유효한 동안 열람할 수 있습니다.\n'
      '동일 고용관계의 계약이 갱신되는 경우 기존 서류 접근 동의는 '
      '갱신된 근무관계에도 승계됩니다.';

  /// 지원 확인 UI에 삽입하는 고지 카드.
  static Widget card(String businessName) =>
      StyledDialogInfoCard.warning(copyFor(businessName));
}
