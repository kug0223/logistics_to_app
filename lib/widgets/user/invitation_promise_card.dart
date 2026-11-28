// lib/widgets/user/invitation_promise_card.dart
//
// [CROSS-DOMAIN-R5.3D] 내가 초대받은 근무 — **수락하면 적용될 조건**.
//
// 이 카드의 모든 값은 Application 스냅샷에서 온다. 공고의 현재 값을
// 여기에 섞지 않는다: 공고는 초대 이후에도 바뀔 수 있고, 바뀌어도 약속은
// 그대로다. 근로자가 결정을 내리는 숫자는 하나여야 한다.
//
// 아래쪽 공고 안내(근무 설명·복장·주차 등)는 현재 정보이고 설명일 뿐이다.

import 'package:flutter/material.dart';

import '../../models/core/application_model.dart';
import '../../models/ui/invitation_projection.dart';
import '../../theme/app_colors.dart';
import '../../theme/light_app_bar_style.dart';
import '../../utils/format_helper.dart';
import '../../utils/expected_daily_wage.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../common/keep_words_text.dart';

class InvitationPromiseCard extends StatelessWidget {
  final InvitationProjection projection;

  /// 원 지원(A) — '다른 업무 제안'일 때만. 비교 맥락이지 수락 대상이 아니다.
  final ApplicationModel? sourceApplication;

  const InvitationPromiseCard({
    super.key,
    required this.projection,
    this.sourceApplication,
  });

  @override
  Widget build(BuildContext context) {
    final app = projection.application;
    final s = ResponsiveHelper.spacing(context, 16);

    return Container(
      margin: EdgeInsets.fromLTRB(s, s, s, 0),
      padding: EdgeInsets.all(s),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mark_email_read_outlined,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.brand),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              // [impl_33 · F294 실측] 320×640@2.0 에서 머리글이 83px 넘쳤다(기존 · before 사본 재현) — 남는 폭 안에서 줄을 바꾼다.
              Flexible(
                child: Text(
                  projection.isAlternativeOffer ? '제안받은 근무' : '내가 초대받은 근무',
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.brand)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),

          // ── 업무 identity ──────────────────────────────────────────
          Text(
            app.selectedWorkType,
            style: ResponsiveHelper.subtitleStyle(context)
                .copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),

          _row(context, Icons.calendar_today_outlined, _dateLabel(app)),
          if (app.startTime.isNotEmpty && app.endTime.isNotEmpty)
            _row(context, Icons.schedule_outlined,
                '${app.startTime} ~ ${app.endTime}'),
          if (app.breakMinutes != null)
            _row(context, Icons.free_breakfast_outlined,
                '휴게 ${app.breakMinutes}분'),
          if (_responseDeadlineLabel() case final deadline?)
            _row(context, Icons.hourglass_bottom_outlined, deadline, words: true),

          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // ── 급여 — 결정의 primary truth ───────────────────────────
          //   공고의 현재 금액을 같은 수준으로 나란히 놓지 않는다.
          // [F293-WAGE-01] 시급 제안은 **제안 지원서 자체의** 시간·휴게·금액으로 하루 예상(주) + 시급(보조).
          //   제안 휴게 null 은 모름 → 확인 필요(임의 0 금지). live 공고와의 차이 안내는 아래 그대로.
          ...() {
            final e = ExpectedDailyWage.forPromise(
                wageType: app.wageType,
                rate: app.wage,
                startTime: app.startTime,
                endTime: app.endTime,
                breakMinutes: app.breakMinutes);
            // [F294-WAGE-01 · C294-WAGE-A/C] 큰 자리에는 확정된 금액만 — 시급 계산 불가면 '예상 금액 확인 필요'(유효 시급만 보조) ·
            //   모르는 유형/누락 단가는 '급여 확인 필요'. 누락 0 을 '0원' 으로 · 모르는 유형을 '시급' 으로 말하지 않는다.
            final label = e.isEstimate ? '하루 예상' : (e.typeUnknown ? '급여' : app.wageTypeLabel);
            final String? amountText = e.isEstimate
                ? FormatHelper.formatWage(e.amount!)
                : (!e.isHourly && !e.typeUnknown && app.wage > 0)
                    ? app.formattedWage
                    : null;
            final amount = amountText ??
                (e.isHourly ? ExpectedWageText.needsCheck : ExpectedWageText.wageUnknown);
            final sub = !e.isHourly
                ? null
                : e.isEstimate
                    ? '${ExpectedWageText.rate(e)} · ${ExpectedWageText.shortNote}'
                    : ExpectedWageText.rate(e);
            return <Widget>[
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: ResponsiveHelper.spacing(context, 6),
                children: [
                  if (label.isNotEmpty)
                    Text(
                      label,
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                    ),
                  Text(
                    amount,
                    style: amountText != null
                        ? ResponsiveHelper.titleStyle(context).copyWith(fontWeight: FontWeight.bold)
                        : ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ],
              ),
              if (sub != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(sub, style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)),
              ],
              if (e.isEstimate) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  ExpectedWageText.disclosure,
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary),
                ),
              ],
            ];
          }(),
          if (projection.hasIndividualCompensation) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              '회원님께 제안된 급여입니다',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.brand)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ],

          // ── 다른 업무 제안이면 기존 지원을 맥락으로 보여준다 ────────
          //   수락 대상은 위의 제안 하나다 — A는 두 번째 수락 대상이 아니다.
          if (projection.isAlternativeOffer) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            // [DU475] 면 grey50 위 글자 대비 — 라벨 · 기존 줄 textTertiary(5.03) · 정리 안내 textSecondary(5.67).
            //   이전 grey500(약 2.6) · grey600(4.42)은 기준 4.5 미달이었다.
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '기존 지원',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.textTertiary),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                  Text(
                    _sourceLine(app),
                    style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.textTertiary)
                        .copyWith(decoration: TextDecoration.lineThrough),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  // [CROSS-DOMAIN-R5.3D.1] 이력은 **남는다** — 사실대로 말한다.
                  //   A는 AUTO_CANCELED / REASSIGNMENT_ACCEPTED로 기록되고
                  //   reassignedToApplicationId로 B와 연결된다.
                  //   없어지는 것은 기록이 아니라 **불이익**이다:
                  //   신뢰도·노쇼·취소 누적 어디에도 들어가지 않는다.
                  KeepWordsText(
                    "수락하면 기존 지원은 '다른 업무로 확정됨'으로 정리돼요.\n"
                    '이 정리는 노쇼로 기록되지 않아요.',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],

          // ── 약속과 현재 공고가 다를 때의 안내 ──────────────────────
          if (projection.driftNotice != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
              decoration: BoxDecoration(
                color: AppColors.warningBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: AppColors.warningDark),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Expanded(
                    child: Text(
                      projection.driftNotice!,
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.warningDark),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── 공고를 읽지 못했을 때 — 초대는 그대로 보인다 ───────────
          if (projection.contextState == InvitationContextState.unavailable) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Text(
              '현재 공고 상세를 불러올 수 없습니다.\n'
              '위 초대 조건은 그대로 유효합니다.',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
          ],

          // ── 지금 수락할 수 없다면 이유를 말한다 ────────────────────
          if (projection.blockedReason != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Text(
              projection.blockedReason!,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600)
                  .copyWith(fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }

  /// [E1-INVITE-DETAIL-KST] 근무일은 KST 자정 instant 다 — **KST 달력일**로 읽는다.
  ///   기기 성분을 쓰면 GMT 기기에서 10/19(월) 초대가 10/18(일)로 보였다(설치 앱 실측).
  String _dateLabel(ApplicationModel app) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    final d = FormatHelper.toKstDate(app.workDate);
    return '${d.month}월 ${d.day}일(${days[d.weekday - 1]})';
  }

  /// [E1-INVITE-DETAIL-KST] 응답 기한 — 목록 카드(`~MM.dd HH:mm 만료`)와 **같은 값**.
  ///
  ///   값은 [ApplicationModel.effectiveInviteDeadline] 하나다(저장 만료·근무 시작·
  ///   서버 수락 마감 중 이른 쪽). 다만 원장에 만료 필드가 **하나도 없으면**
  ///   보이지 않는다 — `초대 + 24시간` 같은 규칙으로 시각을 지어내지 않는다.
  ///   이미 처리된 초대에는 응답할 것이 없으므로 말하지 않는다.
  String? _responseDeadlineLabel() {
    if (projection.acceptability == InvitationAcceptability.alreadyResolved) {
      return null;
    }
    final app = projection.application;
    if (app.inviteExpiresAt == null && app.inviteAcceptDeadline == null) {
      return null;
    }
    final deadline = app.effectiveInviteDeadline;
    if (deadline == null) return null;
    final d = FormatHelper.toKstDate(deadline);
    return '${d.month}월 ${d.day}일 ${FormatHelper.formatTime(deadline)}까지 응답';
  }

  /// 기존 지원 한 줄. 서버가 적어 둔 것만 쓴다 — 모르는 값은 적지 않는다.
  String _sourceLine(ApplicationModel app) {
    final src = sourceApplication;
    if (src != null) {
      // [F293-WAGE-01] 기존 지원도 그 지원서 자체의 약속 조건으로 하루 예상(시급일 때만).
      final expected = ExpectedWageText.combined(ExpectedDailyWage.forPromise(
          wageType: src.wageType, rate: src.wage, startTime: src.startTime,
          endTime: src.endTime, breakMinutes: src.breakMinutes));
      final wage = expected != null ? ' · $expected' : (src.wage > 0 ? ' · ${src.formattedWage}' : '');
      return '${src.selectedWorkType} · ${src.startTime}~${src.endTime}$wage';
    }
    return app.sourceWorkType ?? '기존 지원';
  }

  // [DU475 r2] Row 안 글자에 Flexible 이 없어 B(320 · 2.0)에서 응답 기한 줄이 오른쪽으로 넘쳤다 — 모든 행 글자를 Flexible 로,
  //   응답 기한('11월 19일 22:00까지 응답')만 낱말 단위(keepWords · 원문 semantics)로 둔다. 다른 행 글자는 그대로다.
  Widget _row(BuildContext context, IconData icon, String text, {bool words = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        children: [
          Icon(icon,
              size: ResponsiveHelper.iconSize(context, 15),
              color: AppColors.grey500),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Flexible(
            child: Text(words ? TextLayout.keepWords(text) : text,
                semanticsLabel: words ? text : null,
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey800)),
          ),
        ],
      ),
    );
  }
}

/// [R5.3D] 공고를 읽지 못했을 때의 **독립 상세**.
///
/// 공고가 없다고 초대가 없어지지 않는다. 약속은 Application에 남아 있고,
/// 근로자는 그 조건을 보고 답할 수 있어야 한다.
/// context만 없는 것이지 초대가 없는 것이 아니다 — UNKNOWN ≠ EMPTY.
class InvitationFallbackDetail extends StatelessWidget {
  final InvitationProjection projection;
  final ApplicationModel? sourceApplication;
  final Widget? actions;
  final VoidCallback? onRetryPosting;

  const InvitationFallbackDetail({
    super.key,
    required this.projection,
    this.sourceApplication,
    this.actions,
    this.onRetryPosting,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.grey50,
      appBar: AppBar(
        title: const Text('업무 초대'),
        backgroundColor: Colors.white,
        // [E2-APPBAR-ON-LIGHT] 흰 배경 — 테마의 흰 제목·아이콘을 이 화면만 덮는다.
        titleTextStyle: LightAppBarStyle.title(context),
        iconTheme: LightAppBarStyle.iconTheme,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InvitationPromiseCard(
              projection: projection,
              sourceApplication: sourceApplication,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '근무 안내',
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                  Text(
                    '현재 공고 상세를 불러올 수 없습니다.',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey600),
                  ),
                  if (onRetryPosting != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    OutlinedButton.icon(
                      onPressed: onRetryPosting,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('다시 시도'),
                    ),
                  ],
                ],
              ),
            ),
            // [BOTTOM-BAR-DOUBLE-COUNT] 아래 actions 는
            //   `bottomNavigationBar` 로 달린다 — Scaffold 가 이미 높이를
            //   빼 주므로 본문이 또 비울 필요가 없다.
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ],
        ),
      ),
      bottomNavigationBar:
          actions == null ? null : SafeArea(top: false, child: actions!),
    );
  }
}

/// 급여 숫자 포맷 — 카드 밖에서도 같은 규칙을 쓰도록 노출한다.
String invitationWageLabel(ApplicationModel app) =>
    FormatHelper.formatWage(app.wage);
