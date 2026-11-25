import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/text_layout.dart';
import '../../common/common_widgets.dart';

/// 서류 접근 사전동의 고지 — 문구와 버전의 단일 소유자.
///
/// [DS-08B.5] 지원서에 기록되는 `documentAccessConsentVersion`은
/// "사용자가 실제로 본 문구의 버전"이어야 한다. 문구와 버전이 서로
/// 다른 파일에 흩어지면 한쪽만 고쳤을 때 기록이 거짓이 된다.
/// 그래서 둘을 여기 한 곳에 둔다 — 문구를 고치면 버전도 같이 올린다.
///
/// [CONSENT-R4] **후보(DRAFT · 발급 금지)**. 한 판본 = 카드 2문단 + 동의 전에 여는 '자세히'.
///   상세를 바꾸면 판본도 바뀐다. 카드는 접지 않고 항상 보이며, '자세히'를 열고 닫는 것은
///   화면 상태만 바꾼다(서버 호출·동의 기록 0). 동의는 각 화면의 실행 버튼(지원하기·동의하기·
///   동의하고 초대/제안 수락·동의하고 변경 수락)이 보낸다. 취소는 이번 요청을 보내지 않는다.
///   '관리자'로만 적는다(대표 결정 ②·⑦) — 사업장 이름 인자는 호출부 호환을 위해 받기만 한다.
///   거부 안내 줄은 넣지 않는다(대표 결정 ① · 고지 충분성은 법무 확인 항목).
///
/// 지원 요청을 보내는 경로는 반드시 이 카드를 표시한 뒤 [version]을 전송한다.
///
/// [LEGAL-REVIEW-ID-CONSENT] 동의 문구 및 방식의 법적 적절성은 별도 법무 검토 필요.
class DocumentAccessConsent {
  const DocumentAccessConsent._();

  /// 아래 일반 문안(카드+상세)의 버전. 서버 `DOCUMENT_ACCESS_CONSENT_V4` 와 일치해야 한다.
  ///
  /// 버전 이력
  ///   "2026-08-v1"     신분증만 언급 (구 문구)
  ///   "2026-08-21-v1"  신분증(확정일+7일) + 급여계좌·통장사본 명시
  ///   "2026-09-12-v2"  신분증 종료 기준을 마지막 근무일+7일로 변경 + 계약 갱신 승계 명시
  ///   "2026-09-18-v3"  채용 검토 목적 열람을 명시
  ///   "2026-11-18-v4"  [DRAFT · 동결 전] 2문단(목적→기간) + 동의 전 '자세히'. 받는 쪽 '관리자'.
  ///                    급여계좌·통장사본 = 근무하는 동안 + 마지막 급여 지급부터 30일,
  ///                    지급 이력 없음·지급 기록 확인 필요·지급 뒤 계좌서류 재등록 요청만 남음은
  ///                    마지막 근무일(KST) 0시부터 30일(질문1 확정 · 수식 PP-DELEGATION-20261118).
  ///                    단일 전환(출시 전) —
  ///                    v1~v3 은 새 요청·저장 이력 읽기 모두 근거가 아니다(서버).
  static const String version = '2026-11-18-v4';

  /// 초대·제안 문안(카드+상세)의 버전. 서버 `DOCUMENT_ACCESS_CONSENT_INVITE_V2` 와 일치.
  ///   "2026-10-15-invite-v1"  구 초대 문구(은퇴)
  ///   "2026-11-18-invite-v2"  [DRAFT] 일반 v4 와 같은 구조, 검토 기간만 '수락 기한까지'.
  static const String inviteVersion = '2026-11-18-invite-v2';

  /// 채용 검토 목적 열람을 담은 버전들 — 서버 `REVIEW_PURPOSE_CONSENT_VERSIONS` 와 같은 집합.
  static const Set<String> reviewPurposeVersions = {version, inviteVersion};

  // ── 카드 2문단 ────────────────────────────────────────────────────────
  //   문단 1 = 누구에게·무엇이(행동 = 동의). 문단 2 = 목적 → 기간 두 줄.
  //   문단 안의 '\n' 은 같은 문단 안 줄바꿈이다(문단 사이 간격은 카드가 준다).

  // [CONSENT-R4b · 질문1 답 반영 · 동결 전] 기간 줄은 원칙(근무 중 + 마지막 지급 30일)과
  //   예외의 존재만 적는다 — 예외 세 경우와 정확한 기준은 '자세히'(r4b_copy_policy.md §2 대안표).
  static const String _periodLine =
      '· 근무 확정 후(소득신고·급여처리): 해당 근무관계에서 신분증은 마지막 근무일부터 7일 동안, '
      '급여계좌·통장사본은 근무하는 동안과 마지막 급여 지급부터 30일 동안'
      '(지급 이력이 없는 경우 등은 마지막 근무일부터 30일 동안)';

  // [CONSENT-R4b] 문단 1 은 일반·초대·재배치 공통 문장이다 — 실제 행동 버튼(지원하기 ·
  //   이 조건으로 지원하기 · 동의하기 · 동의하고 초대/제안/변경 수락)이 모두 '지원·동의·수락'에 든다.
  //   r4 의 '동의하면 … 동의합니다' 중복과 재배치 시트의 '지원하기' 불일치를 고친다(r4 감사 §4).
  //   '아래'는 6면·재배치 시트 모두 행동 버튼이 카드 아래에 있다는 배치 사실에 기댄다.
  static const String _actionLine =
      '아래 지원·동의·수락 버튼을 누르면 신분증·급여계좌·통장사본이 관리자에게 보여지는 데 동의합니다.';

  static const List<String> _generalParts = [
    _actionLine,
    '· 채용 검토: 지원이 끝날 때까지\n$_periodLine',
  ];

  static const List<String> _inviteParts = [
    _actionLine,
    '· 채용 검토: 수락 기한까지\n$_periodLine',
  ];

  // ── 동의 전 '자세히' (같은 판본) ───────────────────────────────────────
  //   카드 문단을 되풀이하지 않고 **기준·범위·끝**만 풀어 쓴다.
  //   [DRAFT] A1–A4 + 질문1 확정(two_answers 판정 §2)을 반영. 날짜 경계 문장은 채택 수식
  //   (KST(L) 0시 + 30×24h 배타 · PP-DELEGATION-20261118)과 같은 말이다. 전문·판본 동결은 Codex 판정 요청.

  static const String _dRenewal =
      '‘해당 근무관계’에는 같은 고용관계에서 근로계약이 갱신된 근무도 들어갑니다. '
      '계약이 갱신되면 이 동의는 갱신된 근무에도 그대로 적용됩니다.';

  // [INHERIT 채택(r4 감사 §1-3)] 고지 충분성은 법무 HOLD.
  static const String _dReassign =
      '확정된 근무를 같은 공고의 다른 업무로 바꾸자는 제안을 수락하면, '
      '이 동의는 바뀐 근무에도 그대로 적용됩니다.';

  // [A1 결손 예외] 정상 NO_END 상품은 없다(N-EP2 #4) — 일반 문장은 마지막 근무일 기준만 말한다.
  //   종료일이 기록되지 않은 예외(서버 cr4CurrentWork: 서명한 근로계약 기간이 오늘을 포함)는
  //   '서명한 근로계약 기간 동안'으로 적는다. 시작 전에는 새 열람을 만들지 않는다.
  static const String _dWorking =
      '‘근무하는 동안’은 근무가 확정된 뒤 마지막 근무일이 끝날 때까지입니다. 종료일이 기록되지 '
      '않은 근무는 근무 시작 뒤 서명한 근로계약 기간 동안입니다.';

  // [T30 — '나머지' 기존 규칙] 순수 미결(S2)은 30일을 세지 않는다. 불명이 섞이면 아래 _dLastWork.
  static const String _dLastPayment =
      '‘마지막 급여 지급’은 그 근무관계의 급여를 이체 완료로 처리한 시각 가운데 가장 늦은 '
      '시각입니다(은행 입금 시각이 아닙니다). 지급할 급여가 남아 있는 동안에는 30일을 아직 세지 '
      '않으며(바로 아래 경우는 예외), 이체 완료가 취소되면 다시 지급한 시각부터 셉니다.';

  // [A2 · A3 · A4 — 질문1 확정] L30(줄 급여가 있어도). 경계 = KST(L) 0시 + 30×24h 배타(채택).
  //   [r4c · PP-R4B-A4/UNKNOWN] '지금 등록된 계좌서류에 대한' = 현재 판본 결속 · '확인이 필요한 경우' =
  //   보완 기록 잘림·판본/연결 불명(지급 종결 뒤 A3 L30 — 위임 Codex 결정).
  static const String _dLastWork =
      '다음 경우에는 마지막 근무일(한국 시간) 0시부터 30일 동안 볼 수 있습니다. 지급할 급여 없이 '
      '근무가 끝난 경우, 지급 기록 가운데 확인이 필요한 것이 있는 경우(지급할 급여가 남아 있어도 '
      '같습니다), 급여 지급을 마친 뒤 지금 등록된 계좌서류에 대한 다시 등록 요청만 남았거나 그런 '
      '요청이 있는지 확인이 필요한 경우입니다.';

  // [선지급 T_ONLY 유지]
  static const String _dPrepaid =
      '근무가 끝나기 전에 급여를 모두 받았다면, 근무가 끝난 뒤 볼 수 있는 기간이 짧거나 없을 수 '
      '있습니다.';

  static const String _dEnd =
      '신분증은 마지막 근무일(한국 시간) 0시부터 7일이 지나면, 급여계좌·통장사본은 위 기간이 '
      '지나면 이 근무관계를 근거로 새로 열람할 수 없습니다. 이체를 마친 급여 지급 기록(지급한 '
      '계좌 포함)은 급여 기록으로 남습니다.';

  static const String _dCurrent =
      '관리자에게 보이는 서류는 회원님이 지금 등록해 둔 신분증·급여계좌·통장사본입니다.';

  static const List<String> _generalDetails = [
    '채용 검토를 위한 열람은 해당 지원이 거절·취소·만료되거나 근무가 확정되면 끝납니다.',
    '‘해당 근무관계’는 이 지원으로 확정된 근무입니다. $_dRenewal',
    _dReassign,
    _dWorking,
    _dLastPayment,
    _dLastWork,
    _dPrepaid,
    _dEnd,
    _dCurrent,
  ];

  static const List<String> _inviteDetails = [
    '채용 검토를 위한 열람은 수락 기한이 지나거나, 초대·제안을 거절하거나, 초대·제안이 '
        '취소·만료되거나, 근무가 확정되면 끝납니다.',
    '‘해당 근무관계’는 이 초대·제안을 수락해 확정된 근무입니다. $_dRenewal',
    _dReassign,
    _dWorking,
    _dLastPayment,
    _dLastWork,
    _dPrepaid,
    _dEnd,
    _dCurrent,
  ];

  // ── 공개 API (기존 호출부 모양 유지) ────────────────────────────────────

  /// 일반 카드 문단. [businessName]은 쓰지 않는다(대표 결정 ⑦) — 호출부 호환용.
  static List<String> partsFor(String businessName) => _generalParts;

  /// `partsFor(x).join('\n') == copyFor(x)` 가 항상 참이다.
  static String copyFor(String businessName) => _generalParts.join('\n');

  /// 일반 '자세히' 문단(같은 판본 [version]).
  static List<String> detailsFor(String businessName) => _generalDetails;

  /// 초대·제안 카드 문단.
  static List<String> invitePartsFor(String businessName) => _inviteParts;

  static String inviteCopyFor(String businessName) => _inviteParts.join('\n');

  /// 초대·제안 '자세히' 문단(같은 판본 [inviteVersion]).
  static List<String> inviteDetailsFor(String businessName) => _inviteDetails;

  /// 판본이 가리키는 전문(카드 + 상세) — 지문 대조용. 화면에는 쓰지 않는다.
  static String fullTextFor(String v) => v == inviteVersion
      ? [..._inviteParts, ..._inviteDetails].join('\n')
      : [..._generalParts, ..._generalDetails].join('\n');

  /// 지원 확인 UI에 삽입하는 고지 카드(일반).
  static Widget card(String businessName) => _ConsentCard(
        key: const ValueKey('documentAccessConsentCard'),
        parts: _generalParts,
        details: _generalDetails,
      );

  /// 초대 화면(수락 전 동의·초대/제안 수락)에 삽입하는 고지 카드.
  static Widget inviteCard(String businessName) => _ConsentCard(
        key: const ValueKey('documentAccessConsentInviteCard'),
        parts: _inviteParts,
        details: _inviteDetails,
      );
}

/// 카드(항상 보임) + '자세히'(동의 전에 열 수 있음). 여닫기는 화면 상태만 바꾼다.
///
/// [CONSENT-R4 · D-CB-CONSENT] 정상 사전동의 전문은 경고 안내(E-NOTICE)가 아니다(후속121 §3).
///   예전 카드(StyledDialogInfoCard.warningSegments)는 warning alpha 0.07 면 · 0.22 선 ·
///   warningDark 글자 · 경고 아이콘이었다. 이 후보는 **이 카드 안에서만** 그린다 —
///   공용 StyledDialogInfoCard 의 색은 바꾸지 않는다(공용 위젯 전역 색 치환 0).
///     면·선 = 중립(CommonWidgets.compactCardDecoration · background 면 · borderLight 선)
///     본문 = textPrimary · 아이콘 = 정보(info_outline) 중립 textSecondary(C4)
///     '자세히' = brand 글자 링크(C2) · 상세 = 흰 중립 면(같은 장식)
///   문단 간격 8 · 낱말 단위 줄바꿈(IC1) · 큰 글자에서 아이콘을 글 위로(IC3)는 예전 카드와 같다.
///   기본 배율의 '아이콘을 첫 줄 가운데에'(IC2)는 넣지 않았다 — 시각 대조(V1–V11) 후보다.
class _ConsentCard extends StatefulWidget {
  const _ConsentCard({super.key, required this.parts, required this.details});

  final List<String> parts;
  final List<String> details;

  @override
  State<_ConsentCard> createState() => _ConsentCardState();
}

class _ConsentCardState extends State<_ConsentCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final label = _open ? '자세히 닫기' : '자세히';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NeutralPanel(
          key: const ValueKey('documentAccessConsentBody'),
          segments: widget.parts,
          color: AppColors.background,
          icon: Icons.info_outline,
        ),
        TextButton(
          key: const ValueKey('documentAccessConsentDetailsToggle'),
          // 쓰기 0 — 서버·동의 기록을 부르지 않는다. 이 위젯의 표시 상태만 바꾼다.
          onPressed: () => setState(() => _open = !_open),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 8),
            ),
          ),
          child: Text(
            label,
            semanticsLabel: _open ? '서류 열람 동의 자세히 닫기' : '서류 열람 동의 자세히 보기',
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.brand, fontWeight: FontWeight.w600),
          ),
        ),
        if (_open)
          _NeutralPanel(
            key: const ValueKey('documentAccessConsentDetails'),
            segments: widget.details,
            color: AppColors.surface,
            icon: null,
          ),
      ],
    );
  }
}

/// 중립 면 문단 묶음 — 이 파일 전용(공용 위젯 아님).
class _NeutralPanel extends StatelessWidget {
  const _NeutralPanel({
    super.key,
    required this.segments,
    required this.color,
    required this.icon,
  });

  final List<String> segments;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (i > 0) SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          // 보이는 글자·읽기 이름은 원문 그대로(판본 계약). 줄바꿈만 낱말 단위.
          Text(TextLayout.keepWords(segments[i]),
              semanticsLabel: segments[i], style: style),
        ],
      ],
    );
    Widget inner = body;
    final ic = icon;
    if (ic != null) {
      final iconW = Icon(ic,
          color: AppColors.textSecondary,
          size: ResponsiveHelper.iconSize(context, 18));
      inner = MediaQuery.textScalerOf(context).scale(1) > 1.0
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                iconW,
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                body,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                iconW,
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Expanded(child: body),
              ],
            );
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 11),
      ),
      decoration: CommonWidgets.compactCardDecoration(color: color),
      child: inner,
    );
  }
}
