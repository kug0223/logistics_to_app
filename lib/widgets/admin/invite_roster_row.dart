import 'package:flutter/material.dart';

import '../../models/core/application_model.dart';
import '../../models/ui/invite_capacity_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../common/common_widgets.dart';
import 'invite_state_label.dart';

/// [E2-INVITED-SEAT] 업무별 지원자 창의 초대 한 줄.
///
///   이름 · `MM/dd HH:mm 발송 · MM/dd HH:mm까지 수락`(KST) · 상태 배지 · 상세 진입.
///   상태 문구는 날짜별 명단과 같은 [inviteStateLabelOf] 를 쓴다.
///
///   승인·거절·선택 같은 직접 지원의 행동을 붙이지 않는다. 관리자가 초대에서
///   하는 일은 서류 확인이고, 그것은 [onTap] 이 여는 상세가 서버 판정대로 보여 준다.
///   [onTap] 이 null 이면(사용자 정보를 못 받았다) 진입 화살표도 그리지 않는다.
class InviteRosterRow extends StatelessWidget {
  const InviteRosterRow({
    super.key,
    required this.application,
    required this.name,
    required this.capacity,
    this.onTap,
  });

  final ApplicationModel application;
  final String name;
  final InviteCapacityState capacity;
  final VoidCallback? onTap;

  /// 발송·수락 기한 한 줄 — KST. 모르는 시각은 적지 않는다.
  static String timesLine(ApplicationModel app) {
    final sentAt = app.invitedAt;
    final deadline = app.effectiveInviteDeadline;
    return [
      if (sentAt != null) '${FormatHelper.formatDateTime(sentAt)} 발송',
      if (deadline != null) '${FormatHelper.formatDateTime(deadline)}까지 수락',
    ].join(' · ');
  }

  /// 자리 상태와 **무관하게** 이미 아는 초대 사실 — 응답 대기 · 서류 동의 여부.
  ///
  ///   배지는 capacity 를 모르면 `상태 확인 불가` 다(공용 계약: UNKNOWN 은
  ///   `초대 중` 이라고 말하지 않는다 — 수락을 기다리라는 약속이 되므로).
  ///   그런데 그 한 마디가 이미 아는 것까지 지웠다: 이 초대는 INVITED 로 근로자
  ///   응답을 기다리고 있고, 서류 열람 동의는 했다/안 했다. 그 사실은 모집
  ///   상태와 상관없이 참이라 따로 남긴다. 배지가 이미 같은 말을 하는
  ///   available 에서는 되풀이하지 않는다(null).
  static String? knownFactsLine(
      ApplicationModel app, InviteCapacityState capacity) {
    if (app.status != AppStatus.invited) return null;
    if (capacity == InviteCapacityState.available) return null;
    return app.hasReviewPurposeConsent
        ? '근로자 응답 대기 · 서류 열람 동의함'
        : '근로자 응답 대기 · 서류 열람 동의 전';
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = inviteStateLabelOf(application, capacity: capacity);
    final sub = timesLine(application);
    final facts = knownFactsLine(application, capacity);
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        decoration: CommonWidgets.compactCardDecoration(),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sub.isNotEmpty)
                    // 시각은 사실이라 자르지 않는다 — 좁으면 줄을 바꾼다.
                    Text(
                      sub,
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey500),
                    ),
                  if (facts != null)
                    Text(
                      facts,
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600),
                    ),
                ],
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            // 배지는 남은 폭 안에서 두 줄로 흐른다(날짜별 명단과 같은 처리).
            Flexible(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label,
                  style: ResponsiveHelper.smallStyle(context, color: color)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.grey400),
            ],
          ],
        ),
      ),
    );
  }
}
