// lib/widgets/dialogs/apply/work_selection_card.dart

import 'package:flutter/material.dart';
import '../../../../models/core/work_detail_model.dart';
import '../../../../services/schedule_conflict_service.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../utils/format_helper.dart';
import '../../../../utils/expected_daily_wage.dart';
import '../../../../utils/text_layout.dart';
import '../../../../theme/app_colors.dart';
import '../../work_type_icon.dart';
import '../../common/tax_deduction_badge.dart';

/// 업무 지원 상태
enum WorkApplicationStatus {
  /// 미지원 - 지원 가능
  notApplied,
  
  /// 지원 완료 (PENDING)
  pending,
  
  /// 확정됨 (CONFIRMED)
  confirmed,

  /// [R7-P4.4E.7B] 관리자 초대를 받았고 아직 답하지 않았다 (INVITED)
  ///
  /// 지원과 다른 사건이다. 서버는 초대받은 근무의 **재지원을 막고**
  /// "내 지원 내역에서 초대를 확인해주세요" 를 준다 — 초대는 수락·거절로
  /// 답하는 것이지 다시 지원하는 것이 아니다. 그래서 지원 버튼을 주지 않는다.
  invited,

  /// 마감됨
  closed,
  
  /// 자동취소됨 (시간 충돌)
  autoCanceled,
}

/// 업무 선택 카드
/// 
/// 지원 다이얼로그에서 각 업무를 표시하고 상태에 따른 버튼을 제공
class WorkSelectionCard extends StatelessWidget {
  /// 업무 상세 정보
  final WorkDetailModel workDetail;
  
  /// 현재 지원 상태
  final WorkApplicationStatus status;
  
  /// 시간 충돌 정보
  final ConflictInfo conflictInfo;
  
  /// 지원하기 콜백
  final VoidCallback? onApply;
  
  /// 지원취소 콜백
  final VoidCallback? onCancelApplication;
  
  /// 확정취소 콜백
  final VoidCallback? onCancelConfirm;
  
  /// 로딩 상태
  final bool isLoading;

  /// 슬롯 날짜 (날짜가 지났으면 notApplied 상태도 마감으로 표시)
  final DateTime? slotDate;

  /// 장기공고 여부 — true면 isTimeExpired 체크 생략 (계약 시작일 기준 판단)
  final bool isLongTerm;

  /// [DU280] 누르기 전에 해야 할 일(장기 공고 희망 시작일 선택 등). 있으면 주 행동('지원'·'재지원')을
  ///   누를 수 없게 그리고(onApply 를 주지 않는다) 카드 안에 중립 안내를 둔다.
  ///   **충돌이 아니다** — 배지는 업무 상태 그대로다(사용자 2026-11-10 결정).
  final String? applyGuidance;

  const WorkSelectionCard({
    super.key,
    required this.workDetail,
    required this.status,
    this.conflictInfo = const ConflictInfo(level: ConflictLevel.ok),
    this.onApply,
    this.onCancelApplication,
    this.onCancelConfirm,
    this.isLoading = false,
    this.slotDate,
    this.isLongTerm = false,
    this.applyGuidance,
  });

  // [DU577b] 일급 · 시급 금액 글과 급여 아이콘 = brand(판정170 §5 · BL-04) — 그 밖 유형은 보조색 그대로 · 정산 방식 배지는 이 getter 를 쓰지 않는다.
  Color get _wageColor => workDetail.wageType == 'daily'
      ? AppColors.brand
      : workDetail.wageType == 'hourly'
          ? AppColors.brand
          : AppColors.textSecondary;

  String get _netWorkTime => FormatHelper.calcNetWorkTime(
        workDetail.startTime,
        workDetail.endTime,
        breakMinutes: workDetail.breakMinutes,
      );

  /// 마감 시각 표시 레이블 — slotDate 기준으로 전날/당일 구분
  String? get _deadlineLabel {
    final deadline = workDetail.applicationDeadline;
    if (deadline == null) return null;
    final timeStr = FormatHelper.formatTime(deadline);
    if (slotDate case final slotDate?) {
      final deadlineDay = FormatHelper.toKstDate(deadline);
      final workDay = FormatHelper.toKstDate(slotDate);
      if (deadlineDay.isBefore(workDay)) return '전날 $timeStr까지';
    }
    return '마감 $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 선택 가능 여부 결정
    final bool canInteract = _canInteract();
    
    // [DU274 WC1] 흰 카드·radius 16·grey200 선(시안). 상태는 배지·행동이 말한다(상태별 옅은 면·1.5 상태색 선 제거).
    //   고를 수 없는 카드(차단·마감)는 Opacity 0.6 으로 글자째 흐리지 않고 바탕색 면으로 구별한다 — 글자 대비가 그대로다.
    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: canInteract ? AppColors.surface : AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Padding(
        padding: ResponsiveHelper.cardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단: 업무 정보 + 상태 뱃지
            _buildHeader(context, theme),

            SizedBox(height: ResponsiveHelper.spacing(context, 8)),

            // 중단: 시간 + 급여 + 인원
            _buildDetails(context, theme),

            // [DU280] 할 일 안내(중립) — 주 행동을 그리는 상태에서만
            if (applyGuidance != null && _showsPrimaryAction)
              _buildGuidance(context),

            // 충돌 경고 메시지 (확정 상태면 숨김, 예약 메시지도 숨김)
            if (conflictInfo.hasConflict &&
                status != WorkApplicationStatus.confirmed &&
                conflictInfo.message != '예약')
              _buildConflictMessage(context),
            // [DU274] 끝의 여분 12 간격을 걷었다 — 위아래 여백은 cardPadding 하나다.
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 상단: 업무 정보 + 상태 뱃지
  // ═══════════════════════════════════════════════════════════

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    // 업무 아이콘
    final icon = WorkTypeIcon.buildWithBackground(
      iconString: workDetail.workTypeIcon,
      iconColor: workDetail.workTypeColor,
      backgroundColor: workDetail.workTypeBackgroundColor,
      size: ResponsiveHelper.spacing(context, 16),
      containerSize: ResponsiveHelper.spacing(context, 32),
    );
    // 업무명 — [DU274 WC2] bodyStyle 기본 grey700 → 본문색. 문구는 원문(시험 계약).
    final name = Text(
      workDetail.workType,
      style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary).copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
    final gap = SizedBox(width: ResponsiveHelper.spacing(context, 10));

    // [DU274 WC5] 큰 글자: 아이콘·업무명·배지·행동 넷이 한 줄이면 업무명이 한 음절씩 세로로 끊기고
    //   320 에서 42px 넘쳤다 — '아이콘·업무명' / '배지 … 행동' 두 줄로 나눈다.
    if (MediaQuery.textScalerOf(context).scale(10) >= 13) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [icon, gap, Expanded(child: name)]),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: ResponsiveHelper.spacing(context, 8),
              runSpacing: ResponsiveHelper.spacing(context, 4),
              children: [
                _buildStatusBadge(context),
                _buildInlineActionButton(context, theme),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        icon,
        gap,
        Expanded(child: name),

        // 상태 뱃지
        _buildStatusBadge(context),

        SizedBox(width: ResponsiveHelper.spacing(context, 8)),

        // 액션 버튼 (인라인)
        _buildInlineActionButton(context, theme),
      ],
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    String text;
    Color bgColor;
    Color textColor;

    // ✅ 확정 상태면 최우선 (시간충돌보다 우선)
    if (status == WorkApplicationStatus.confirmed) {
      text = '확정';
      bgColor = AppColors.successBg;
      textColor = AppColors.successDark;
    } else if (conflictInfo.level == ConflictLevel.blocked) {
      // 충돌이 BLOCKED면 (미확정 상태에서만)
      // ✅ 예약 상태면 '예약' 표시
      if (conflictInfo.message == '예약') {
        text = '예약';
        bgColor = AppColors.warningBg;
        textColor = AppColors.warningDark;
      } else {
        text = '시간충돌';
        bgColor = AppColors.errorBg;
        textColor = AppColors.errorDark;
      }
    } else {
      switch (status) {
        case WorkApplicationStatus.confirmed:
          // 위에서 처리됨
          text = '확정';
          bgColor = AppColors.successBg;
          textColor = AppColors.successDark;
          break;
        case WorkApplicationStatus.pending:
          text = '지원완료';
          bgColor = AppColors.infoBg;
          textColor = AppColors.infoDeep; // [DU274 WC3] infoDark 4.03 → infoDeep(같은 파랑, 4.5 이상)
          break;
        case WorkApplicationStatus.invited:
          text = '초대 확인';
          bgColor = AppColors.warningBg;
          textColor = AppColors.warningDark;
          break;
        case WorkApplicationStatus.closed:
          text = '마감';
          bgColor = AppColors.grey100; // [DU274 WC3] grey200/grey600 3.97 → 종료 중립 쌍(RS-H2 와 같다)
          textColor = AppColors.textSecondary;
          break;
        case WorkApplicationStatus.autoCanceled:
          text = '자동취소';
          bgColor = AppColors.warningBg;
          textColor = AppColors.warningDark;
          break;
      case WorkApplicationStatus.notApplied:
          if (_isClosed) {
            text = '마감';
            bgColor = AppColors.grey100;
            textColor = AppColors.textSecondary;
          } else {
            // [R7-P1-2] 모집중 = 진행 상태. green 은 지원완료·확정에 남긴다.
            text = '모집중';
            bgColor = AppColors.infoBg;
            textColor = AppColors.infoDeep; // [DU274 WC3] infoDark 4.03 → infoDeep(RS-A 와 같은 쌍)
          }
          break;
      }
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 8),
        ),
      ),
      child: Text(
        text,
        style: ResponsiveHelper.smallStyle(context, color: textColor).copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 중단: 시간 + 급여 + 인원
  // ═══════════════════════════════════════════════════════════

  /// 메타데이터 한 조각 — 아이콘 + 글자.
  ///
  /// [R7-P4.4E.6A] `Wrap` 은 자식에게 **maxWidth: Infinity** 를 준다. 그래서
  ///   `Row(mainAxisSize: min)` 조각은 줄어들 수 있는 자식이 있어도 절대
  ///   줄어들지 않는다. 320dp 에서 시간 조각이 242.3px 를 요구하는데 가용
  ///   폭은 226.9px 였고 그대로 12px 넘쳤다.
  ///   조각을 가용 폭으로 묶어 주면 글자가 조각 안에서 줄을 바꾼다 —
  ///   근무시간·급여는 핵심 사실이므로 ellipsis 로 감추지 않는다.
  Widget _metaChunk(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required double maxWidth,
    required List<Widget> texts,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: ResponsiveHelper.spacing(context, 1),
            ),
            child: Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 14),
              color: iconColor,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Flexible(
            child: Wrap(
              spacing: ResponsiveHelper.spacing(context, 3),
              runSpacing: ResponsiveHelper.spacing(context, 2),
              crossAxisAlignment: WrapCrossAlignment.center,
              children: texts,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(BuildContext context, ThemeData theme) {
    return Padding(
      padding: EdgeInsets.only(
        left: ResponsiveHelper.spacing(context, 42),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 조각들이 쓸 수 있는 실제 폭 — Wrap 이 자식에게 주지 않는 값이다.
          final maxW = constraints.maxWidth;
          return Wrap(
            spacing: ResponsiveHelper.spacing(context, 12),
            runSpacing: ResponsiveHelper.spacing(context, 4),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 근무시간 + 순근무시간
              _metaChunk(
                context,
                icon: Icons.access_time,
                iconColor: AppColors.textSecondary, // [DU274 WC6] grey500 2.68 → 보조색
                maxWidth: maxW,
                texts: [
                  Text(
                    workDetail.timeRange,
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary),
                  ),
                  if (_netWorkTime.isNotEmpty)
                    Text(
                      '($_netWorkTime)',
                      // [DU274 WC6] tiny grey500 2.68 → small 보조색
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                    ),
                ],
              ),
              // 지원 마감 시각 (단기 TO, 마감 정보 있을 때)
              if (!isLongTerm && _deadlineLabel != null)
                _metaChunk(
                  context,
                  icon: Icons.timer_off_outlined,
                  iconColor: AppColors.warningDark,
                  maxWidth: maxW,
                  texts: [
                    Text(
                      _deadlineLabel!,
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: AppColors.warningDark,
                      ),
                    ),
                  ],
                ),
              // 급여 (아이콘 + 금액/유형) — 배지는 별도 Wrap 아이템으로 분리해 overflow 방지
              _metaChunk(
                context,
                icon: Icons.payments_outlined,
                iconColor: _wageColor,
                maxWidth: maxW,
                texts: [
                  Text(
                    // [F293-WAGE-01] 시급 업무는 하루 예상(주) + 시급(보조) — 이 업무 1회 기준.
                    ExpectedWageText.combined(ExpectedDailyWage.forWorkDetail(workDetail)) ??
                        '${ExpectedWageText.rawWage(workDetail.wage)}/${workDetail.wageTypeLabel}',
                    style: ResponsiveHelper.smallStyle(context, color: _wageColor)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
          // 정산방식 배지 — Wrap 아이템으로 독립 분리 (좁은 화면에서 다음 줄 개행)
          if (workDetail.payScheduleTypeLabel.isNotEmpty)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 6),
                vertical: 1,
              ),
              decoration: BoxDecoration(
                // [DU577b] 정산 방식 배지 = 중립 grey100 면 · textSecondary 글(판정170 §5) — 급여 금액 색과 분리.
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                workDetail.payScheduleTypeLabel,
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
              // 입금일 상세 (주급/월급 등 날짜·시간 있을 때만)
              if (workDetail.payScheduleDetail.isNotEmpty)
                _metaChunk(
                  context,
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: AppColors.textSecondary,
                  maxWidth: maxW,
                  texts: [
                    Text(
                      '${workDetail.payScheduleDetail} 입금',
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                    ),
                  ],
                ),

              // 모집 인원
              if (workDetail.requiredCount > 0)
                _metaChunk(
                  context,
                  icon: Icons.people_outline,
                  iconColor: AppColors.textSecondary,
                  maxWidth: maxW,
                  texts: [
                    Text(
                      '${workDetail.requiredCount}명 모집',
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                    ),
                  ],
                ),

              // 공제 방식 (none이면 자동으로 SizedBox.shrink)
              TaxDeductionBadge.chip(taxDeductionType: workDetail.taxDeductionType),
            ],
          );
        },
      ),
    );
  }

  /// 인라인 액션 — [DU274 WC4] UI-1(사용자 확인): 주 행동만 대표색 채움, 보조·위험은 테두리 없는 글자,
  ///   누를 수 없는 상태는 버튼 모양을 쓰지 않는다. 누를 수 있는 것은 터치 48.
  ///   (이전: 채움 위 흰 글자 작은 상자 — 터치 약 28, '취소' 2.68·'확정취소' 3.68·'재지원' 2.16,
  ///   누를 수 없는 '불가'·'마감'도 버튼 모양이었다.)
  Widget _buildInlineActionButton(BuildContext context, ThemeData theme) {
    // 로딩 중 — 48 칸 안에 둬서 머리 높이가 바뀌지 않는다
    if (isLoading) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: ResponsiveHelper.spacing(context, 20),
            height: ResponsiveHelper.spacing(context, 20),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.primaryColor,
            ),
          ),
        ),
      );
    }

    // ✅ 확정 상태면 최우선 (BLOCKED보다 먼저)
    if (status == WorkApplicationStatus.confirmed) {
      return _textAction(context, '확정취소', Icons.cancel_outlined, onCancelConfirm, AppColors.errorDark);
    }

    // BLOCKED면 선택 불가
    if (conflictInfo.level == ConflictLevel.blocked) {
      return _statusNote(context, '불가', Icons.block, AppColors.textSecondary);
    }

    // 상태별 버튼
    switch (status) {
      case WorkApplicationStatus.notApplied:
        if (_isClosed) {
          return _statusNote(context, '마감', Icons.block, AppColors.textSecondary);
        }
        return _primaryAction(context, '지원', Icons.send, onApply);

      case WorkApplicationStatus.pending:
        return _textAction(context, '취소', Icons.close, onCancelApplication, AppColors.textSecondary);

      case WorkApplicationStatus.invited:
        // 지원 버튼을 주지 않는다 — 여기서 할 일은 초대에 답하는 것이고,
        // 그건 내 지원 내역에서 한다. 서버도 재지원을 막는다.
        return _statusNote(context, '초대 확인', Icons.mail_outline, AppColors.warningDark);

      case WorkApplicationStatus.confirmed:
        // ✅ 확정취소 버튼 활성화
        return _textAction(context, '확정취소', Icons.cancel_outlined, onCancelConfirm, AppColors.errorDark);

      case WorkApplicationStatus.closed:
        return _statusNote(context, '마감', Icons.block, AppColors.textSecondary);

      case WorkApplicationStatus.autoCanceled:
        return _primaryAction(context, '재지원', Icons.refresh, onApply);
    }
  }

  /// 주 행동('지원'·'재지원')을 그리는 상태인가 — _buildInlineActionButton 과 같은 분기.
  bool get _showsPrimaryAction {
    if (isLoading || status == WorkApplicationStatus.confirmed) return false;
    if (conflictInfo.level == ConflictLevel.blocked) return false;
    if (status == WorkApplicationStatus.notApplied) return !_isClosed;
    return status == WorkApplicationStatus.autoCanceled;
  }

  /// [DU280] 할 일 안내 — 바탕색 면·보조색·안내 아이콘(빨강 없음). 낱말 단위, 읽기 이름 원문.
  Widget _buildGuidance(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: ResponsiveHelper.iconSize(context, 18),
            color: AppColors.textSecondary,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              TextLayout.keepWords(applyGuidance!),
              semanticsLabel: applyGuidance,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// 주 행동('지원'·'재지원') — 대표색 채움·흰 글자·터치 48.
  Widget _primaryAction(BuildContext context, String text, IconData icon, VoidCallback? onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: ResponsiveHelper.iconSize(context, 16)),
      label: Text(text),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        // [DU280 ND3] 누를 수 없을 때(할 일 남음·제출 중) 중립 비활성 면 — DU272 비활성 CTA 와 같다
        disabledBackgroundColor: AppColors.grey200,
        disabledForegroundColor: AppColors.textSecondary,
        elevation: 0,
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 14)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: ResponsiveHelper.smallStyle(context, fontWeight: FontWeight.w700),
      ),
    );
  }

  /// 보조('취소')·위험('확정취소') 행동 — 테두리 없는 글자·터치 48.
  Widget _textAction(BuildContext context, String text, IconData icon, VoidCallback? onTap, Color color) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: ResponsiveHelper.iconSize(context, 16)),
      label: Text(text),
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 10)),
        textStyle: ResponsiveHelper.smallStyle(context, fontWeight: FontWeight.w700),
      ),
    );
  }

  /// 누를 수 없는 상태 표시('불가'·'마감'·'초대 확인') — 버튼 모양을 쓰지 않는다(눌러 볼 것처럼 보이지 않게).
  Widget _statusNote(BuildContext context, String text, IconData icon, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 16), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            text,
            style: ResponsiveHelper.smallStyle(context, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 충돌 경고 메시지
  // ═══════════════════════════════════════════════════════════

  Widget _buildConflictMessage(BuildContext context) {
    final isBlocked = conflictInfo.level == ConflictLevel.blocked;
    
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: isBlocked ? AppColors.errorBg : AppColors.warningBg,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 8),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isBlocked ? Icons.block : Icons.warning_amber_rounded,
            size: ResponsiveHelper.iconSize(context, 18),
            color: isBlocked ? AppColors.errorDark : AppColors.warningDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            // [DU274 WC7] 낱말 안에서 끊지 않는다(W360 에서 '없/어요' 로 갈렸다)
            child: Text(
              TextLayout.keepWords(conflictInfo.message ?? ''),
              style: ResponsiveHelper.smallStyle(
                context,
                color: isBlocked ? AppColors.errorDark : AppColors.warningDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 헬퍼 메서드
  // ═══════════════════════════════════════════════════════════

  /// 날짜·마감·인원 기준 마감 여부
  ///
  /// 장기공고는 slotDate(TO 시작일) 과거 여부 체크를 제외한다.
  ///   사용자가 캘린더에서 희망 시작일을 직접 선택하므로 TO 시작일이
  ///   과거여도 지원 가능한 날짜가 남아 있을 수 있다.
  /// 단기공고는 slotDate가 과거이면 마감 처리.
  bool get _isClosed {
    if (workDetail.isFull || workDetail.isClosed) return true;
    if (!isLongTerm && workDetail.isTimeExpired) return true;
    if (!isLongTerm && slotDate != null) {
      final now = DateTime.now();
      return FormatHelper.toKstDate(slotDate!)
          .isBefore(FormatHelper.toKstDate(now));
    }
    return false;
  }

  bool _canInteract() {
    // ✅ 확정 상태면 항상 활성화 (확정취소 가능)
    if (status == WorkApplicationStatus.confirmed) return true;
    
    // BLOCKED면 불가
    if (conflictInfo.level == ConflictLevel.blocked) return false;
    
    // 마감이면 불가
    if (status == WorkApplicationStatus.closed) return false;
    if (_isClosed && status == WorkApplicationStatus.notApplied) return false;
    
    // autoCanceled는 재지원 가능
    return true;
  }
}