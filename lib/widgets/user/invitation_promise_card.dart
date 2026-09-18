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
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';

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
              Text(
                projection.isAlternativeOffer ? '제안받은 근무' : '내가 초대받은 근무',
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.brand)
                    .copyWith(fontWeight: FontWeight.bold),
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

          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // ── 급여 — 결정의 primary truth ───────────────────────────
          //   공고의 현재 금액을 같은 수준으로 나란히 놓지 않는다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (app.wageTypeLabel.isNotEmpty) ...[
                Text(
                  app.wageTypeLabel,
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey600),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              ],
              Text(
                app.formattedWage,
                style: ResponsiveHelper.titleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
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
                        color: AppColors.grey500),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                  Text(
                    _sourceLine(app),
                    style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey600)
                        .copyWith(decoration: TextDecoration.lineThrough),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    '수락하면 기존 지원은 자동으로 정리됩니다.\n'
                    '취소 이력이나 불이익은 남지 않아요.',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.grey600),
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

  String _dateLabel(ApplicationModel app) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    final d = app.workDate;
    return '${d.month}월 ${d.day}일(${days[d.weekday - 1]})';
  }

  /// 기존 지원 한 줄. 서버가 적어 둔 것만 쓴다 — 모르는 값은 적지 않는다.
  String _sourceLine(ApplicationModel app) {
    final src = sourceApplication;
    if (src != null) {
      final wage = src.wage > 0 ? ' · ${src.formattedWage}' : '';
      return '${src.selectedWorkType} · ${src.startTime}~${src.endTime}$wage';
    }
    return app.sourceWorkType ?? '기존 지원';
  }

  Widget _row(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        children: [
          Icon(icon,
              size: ResponsiveHelper.iconSize(context, 15),
              color: AppColors.grey500),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text(text,
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey800)),
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
            SizedBox(height: ResponsiveHelper.spacing(context, 100)),
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
