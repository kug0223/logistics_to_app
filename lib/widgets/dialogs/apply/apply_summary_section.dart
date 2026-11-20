// lib/widgets/dialogs/apply/apply_summary_section.dart

import 'package:flutter/material.dart';
import '../../../../utils/format_helper.dart';
import '../../../../models/core/application_model.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../theme/app_colors.dart';
import '../../../../utils/text_layout.dart';
import '../../../../widgets/common/first_line_icon.dart';

/// 내 지원 일정 섹션 (컴팩트)
///
/// 사용자의 전체 활성 지원 내역(모든 공고 포함)을 최대 2건 미리보기로 표시.
/// - 대기 상태 → Orange 배지 '대기'
/// - 확정 상태 → Green 배지 '확정'
/// - currentToId의 공고 지원 → '현재 공고' 라벨
/// - 3건 이상이면 '전체보기 >' 표시
class ApplySummarySection extends StatelessWidget {
  /// 사용자의 전체 지원 목록 (PENDING + CONFIRMED 포함)
  final List<ApplicationModel> myApplications;

  /// 현재 보고 있는 공고 ID — 이 TO의 지원에 '현재 공고' 라벨 표시
  final String? currentToId;

  final String emptyMessage;

  /// true이면 로드 실패 안내 표시 (emptyMessage 대신)
  final bool isLoadError;

  const ApplySummarySection({
    super.key,
    required this.myApplications,
    this.currentToId,
    this.emptyMessage = '오늘 이후 예정된 지원 건이 없습니다',
    this.isLoadError = false,
  });

  // ─── 활성 지원만 필터 ───────────────────────────────────
  List<ApplicationModel> get _active {
    final today = DateTime.now();
    final todayOnly = FormatHelper.toKstDate(today);

    return myApplications.where((app) {
      if (AppStatus.inactiveStates.contains(app.status)) return false;
      // [SIM-EXPIRED-INVITE-SUMMARY] 만료된 초대는 일정이 아니다. 걸러지지 않으면
      //   아래에서 '확정이 아닌 것 = 대기'로 그려져, '내 지원'에선 "초대 종료"인 건이
      //   여기선 "대기"로 보였다(DEVICE 10-18). 전역 `inactiveStates` 는 지원서 조회·
      //   상태 전이 판정도 쓰므로 바꾸지 않고 이 요약에서만 뺀다.
      if (app.status == AppStatus.expired) return false;
      // 장기 지원 중 퇴사 완료된 건 제외
      if (app.isLongTermApplication && app.isTerminationApproved) return false;
      // 단기 지원은 오늘 이전 날짜 제외 (장기는 계약 기간 내내 유지)
      if (!app.isLongTermApplication) {
        final workDateOnly = FormatHelper.toKstDate(app.workDate);
        if (workDateOnly.isBefore(todayOnly)) return false;
      }
      return true;
    }).toList();
  }

  // ─── 날짜순 정렬, 현재 공고 먼저 ─────────────────────────
  List<ApplicationModel> get _sorted {
    final all = _active;
    all.sort((a, b) {
      final aIsCurrent = (currentToId != null && a.toId == currentToId) ? 0 : 1;
      final bIsCurrent = (currentToId != null && b.toId == currentToId) ? 0 : 1;
      final cmpCurrent = aIsCurrent.compareTo(bIsCurrent);
      if (cmpCurrent != 0) return cmpCurrent;
      return a.workDate.compareTo(b.workDate);
    });
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final sorted = _sorted;
    final total = sorted.length;
    final preview = sorted.take(2).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더 row: 타이틀 + 건수 배지 + "전체보기 >"
        // [DU446] 제목 + Spacer 는 큰 글자(320 · 2.0)에서 가용폭을 넘길 수 있었다(Spacer 는 모자란 폭을 만들지 못한다).
        //   제목은 Flexible(낱말 사이 줄바꿈 · 읽기는 원문), 옆 칸이 모자라면 '전체보기 >'를 아래 줄 오른쪽으로 내린다.
        LayoutBuilder(builder: (_, box) {
          final icon = ResponsiveHelper.iconSize(context, 15);
          final gap = ResponsiveHelper.spacing(context, 5);
          final more = total > 2
              ? Text(
                  '전체보기 >',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.infoDark, fontWeight: FontWeight.w600),
                )
              : null;
          final lead = <Widget>[
            Icon(Icons.event_note_outlined, size: icon, color: AppColors.grey600),
            SizedBox(width: gap),
            Flexible(
              child: Text(
                TextLayout.keepWords('내 지원 일정'),
                semanticsLabel: '내 지원 일정',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey700, fontWeight: FontWeight.w600),
              ),
            ),
            if (total > 0) ...[
              SizedBox(width: gap),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 6),
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$total건',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey600, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ];
          if (more == null || TextLayout.fits(context, box.maxWidth - icon - gap, 200)) {
            return Row(children: [...lead, if (more != null) ...[const Spacer(), more]]);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: lead),
              Align(alignment: Alignment.centerRight, child: more),
            ],
          );
        }),
        SizedBox(height: ResponsiveHelper.spacing(context, 7)),
        // 내용
        if (isLoadError)
          _buildErrorState(context)
        else if (total == 0)
          _buildEmptyState(context)
        else
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 10),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Column(
              children: preview.asMap().entries.map((e) {
                final idx = e.key;
                final app = e.value;
                return Column(
                  children: [
                    _buildAppItem(context, app),
                    if (idx < preview.length - 1)
                      Divider(
                        height: ResponsiveHelper.spacing(context, 12),
                        color: AppColors.grey200,
                      ),
                  ],
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  // ─── 빈 상태 ──────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 4)),
      child: Text(
        emptyMessage,
        // [DU446] grey400(흰 위 1.88) → textTertiary(5.25).
        style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 4)),
      // [DU447] 고정 글이 큰 글자(320 · 2.0)에서 칸 밖으로 넘쳤다 — 글을 Flexible 로 두고 낱말 사이에서만 줄을 바꾼다(읽기는 원문).
      //   아이콘은 첫 줄에 맞춘다(공용 FirstLineIcon · 크기 그대로). [DU446] 글자 grey500(2.68) → textTertiary.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FirstLineIcon(Icons.cloud_off_outlined,
              size: ResponsiveHelper.iconSize(context, 13),
              color: AppColors.warning,
              textStyle: ResponsiveHelper.tinyStyle(context)),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Flexible(
            child: Text(
              TextLayout.keepWords('지원 현황을 불러오지 못했습니다'),
              semanticsLabel: '지원 현황을 불러오지 못했습니다',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 지원 아이템 ───────────────────────────────────────

  Widget _buildAppItem(BuildContext context, ApplicationModel app) {
    final isConfirmed = AppStatus.confirmedStatuses.contains(app.status);
    final isCurrent = currentToId != null && app.toId == currentToId;
    final timeRange = '${app.startTime} ~ ${app.endTime}';
    final dateLabel = app.isLongTermApplication
        ? '${FormatHelper.formatDateShort(app.workDate)} 시작'
        : FormatHelper.formatDateShort(app.workDate);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 상태 점
        Padding(
          padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 5)),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isConfirmed ? AppColors.success : AppColors.warning,
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        // 날짜 + 현재공고 라벨 + 업무/시간/사업장
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // [DU446] 날짜 + '현재 공고' 칩은 Row 라 큰 글자에서 넘칠 수 있었다 — 칸이 모자라면 칩이 다음 줄로 간다(Wrap).
              Wrap(
                spacing: ResponsiveHelper.spacing(context, 4),
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    dateLabel,
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.grey600,
                        fontWeight: FontWeight.w600),
                  ),
                  if (isCurrent) ...[
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 4),
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '현재 공고',
                        // [DU446] infoDark(infoBg 위 4.03) → infoDeep(같은 파랑 · 지원 대화 업무 카드 DU274 WC3 와 같은 짝).
                        style: ResponsiveHelper.tinyStyle(
                          context,
                          color: AppColors.infoDeep,
                          fontWeight: FontWeight.w700,
                        ).copyWith(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: 1),
              Text(
                '${app.selectedWorkType}  $timeRange',
                // [DU446] grey500(옅은 면 위 2.6) → textSecondary · 사업장명 grey400(1.8) → textTertiary.
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
              ),
              if (app.businessName.isNotEmpty)
                // [DU447] 사업장명이 음절에서 끊겼다('테스트 사 / 업장') — 이름 규칙(TextLayout.identity · 읽기는 원문).
                Text(
                  TextLayout.identity(app.businessName),
                  semanticsLabel: app.businessName,
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary),
                ),
            ],
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        // 상태 배지 — 대기: Orange, 확정: Green
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 6),
            vertical: ResponsiveHelper.spacing(context, 2),
          ),
          decoration: BoxDecoration(
            color: isConfirmed ? AppColors.successBg : AppColors.warningBg,
            borderRadius: BorderRadius.circular(
                ResponsiveHelper.spacing(context, 4)),
          ),
          child: Text(
            isConfirmed ? '확정' : '대기',
            style: ResponsiveHelper.tinyStyle(
              context,
              color: isConfirmed ? AppColors.successDark : AppColors.warningDark,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
