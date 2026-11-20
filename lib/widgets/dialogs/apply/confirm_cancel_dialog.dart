// lib/widgets/dialogs/apply/confirm_cancel_dialog.dart

import 'package:flutter/material.dart';
import '../../../../utils/format_helper.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../theme/app_colors.dart';
import '../../../../utils/text_layout.dart';
import '../../../../services/schedule_conflict_service.dart';
import '../styled_dialog.dart';

/// 확정 취소 다이얼로그 결과
enum ConfirmCancelResult {
  /// 취소 진행
  proceed,
  
  /// 돌아가기
  cancel,
}

/// 확정 취소 경고 다이얼로그
/// 
/// 버스 예매 스타일로 취소 정책과 패널티를 안내
class ConfirmCancelDialog extends StatelessWidget {
  /// 근무 날짜
  final DateTime workDate;
  
  /// 업무명
  final String workType;
  
  /// 근무 시간
  final String timeRange;
  
  /// 사업장명
  final String businessName;
  
  /// 현재 노쇼 횟수
  final int currentNoShowCount;
  
  /// 패널티 적용 여부 (근무 시작 5분 전 이후 취소)
  final bool hasPenalty;

  const ConfirmCancelDialog({
    super.key,
    required this.workDate,
    required this.workType,
    required this.timeRange,
    required this.businessName,
    required this.currentNoShowCount,
    required this.hasPenalty,
  });

  /// 다이얼로그 표시
  ///
  /// [scheduledStartTime] 근무 시작 시각 (HH:mm 형식). null이면 당일 기준으로 fallback.
  static Future<ConfirmCancelResult?> show({
    required BuildContext context,
    required DateTime workDate,
    required String workType,
    required String timeRange,
    required String businessName,
    required int currentNoShowCount,
    String? scheduledStartTime,
    // [SIM-RECONFIRM-DECLINE-ALIGN] 판정 시각 — 화면이 쓰는 시계를 그대로 넘길 수 있게.
    //   기본값은 지금이다(기존 호출부 동작 그대로).
    DateTime? now,
  }) async {
    // [GAP-1] canonical 5-minute policy: 근무 시작 5분 전 이후 취소 → 패널티
    //
    // [E1-CUTOFF] 서버(`callableCancelConfirmedApplication`)와 **같은 식**을
    //   쓴다. 예전에는 `toKstDate()` 가 돌려준 **UTC 자정**에 근무 시각을
    //   더해 시작이 9시간 늦게 잡혔고(기기 시간대 무관), 그 구간에서는
    //   이 확인창이 **경고 없이** 취소를 진행시켰다 — 사용자는 노쇼가
    //   기록되는 줄 모르고 결정하게 된다.
    //   시각을 못 읽으면 기존 당일 기준 fallback 그대로다.
    final at = now ?? DateTime.now();
    final hasPenalty = ScheduleConflictService().isNoShowEquivalentCancel(
          workDate: workDate,
          startTime: scheduledStartTime ?? '',
          now: at,
        ) ??
        (() {
          final workDay = FormatHelper.toKstDate(workDate);
          final today = FormatHelper.toKstDate(at);
          return workDay.isAtSameMomentAs(today) || workDay.isBefore(today);
        })();

    return showDialog<ConfirmCancelResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConfirmCancelDialog(
        workDate: workDate,
        workType: workType,
        timeRange: timeRange,
        businessName: businessName,
        currentNoShowCount: currentNoShowCount,
        hasPenalty: hasPenalty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StyledDialog(
      title: TextLayout.keepWords('확정 취소 안내'), // [DU265] B320 '안/내' 끊김(공용 StyledDialog 제목)
      icon: Icons.warning_amber_rounded,
      headerColor: AppColors.errorDark, // [DU265] 확인 순간의 위험색은 유지하되 읽히게(아이콘 상자)
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 근무 정보 카드
          _buildWorkInfoCard(context, theme),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 취소 정책 안내
          _buildPolicySection(context, theme),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 현재 상태 + 경고
          _buildCurrentStatus(context, theme),
        ],
      ),
      actions: [
        // 돌아가기 버튼
        StyledDialogButton.cancel(
          text: '돌아가기',
          onPressed: () => Navigator.pop(context, ConfirmCancelResult.cancel),
        ),
        
        // 취소 진행 버튼
        StyledDialogButton(
          text: '취소 진행',
          // [DU265] error(#F44336, 흰 글자 3.68) → errorDark(약 6.6)
          backgroundColor: AppColors.errorDark,
          foregroundColor: Colors.white,
          onPressed: () => Navigator.pop(context, ConfirmCancelResult.proceed),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 근무 정보 카드
  // ═══════════════════════════════════════════════════════════

  Widget _buildWorkInfoCard(
    BuildContext context,
    ThemeData theme,
  ) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 사업장명
          // [DU265] 이름 단위 줄바꿈·본문색 명시
          Text(
            TextLayout.identity(businessName),
            semanticsLabel: businessName,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 날짜 + 업무명
          // [DU265] Row → Wrap(좁은 폭·큰 글자에서 업무명이 다음 줄로), 업무명 말줄임 제거·낱말 단위.
          //   아이콘 grey600 → textSecondary, 글자 grey700 → 본문색.
          Wrap(
            spacing: ResponsiveHelper.spacing(context, 16),
            runSpacing: ResponsiveHelper.spacing(context, 4),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Text(
                    FormatHelper.formatDate(workDate),
                    style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.work_outline,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Flexible(
                    child: Text(
                      TextLayout.keepWords(workType),
                      semanticsLabel: workType,
                      style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ],
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 4)),

          // 시간
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.textSecondary, // [DU265] grey600
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                timeRange,
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary), // [DU265] grey700
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 취소 정책 안내
  // ═══════════════════════════════════════════════════════════

  Widget _buildPolicySection(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 12),
        ),
        border: Border.all(color: AppColors.grey300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 제목
          Row(
            children: [
              Icon(
                Icons.policy_outlined,
                size: ResponsiveHelper.iconSize(context, 18),
                color: theme.primaryColor,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '취소 정책',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.primaryColor,
                ),
              ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 1일 전 취소
          _buildPolicyItem(
            context,
            icon: Icons.check_circle,
            iconColor: AppColors.successDark, // [DU265] success(2.78)
            bg: AppColors.successBg,
            title: '근무 1일 전까지',
            description: '패널티 없음',
            isHighlighted: !hasPenalty,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          
          // 근무 시작 5분 전부터 취소
          _buildPolicyItem(
            context,
            icon: Icons.warning,
            iconColor: AppColors.errorDark, // [DU265] error
            bg: AppColors.errorBg,
            title: '근무 시작 5분 전부터 취소',
            description: '노쇼 1회 기록\n→ 3회 누적 시 1일 지원 제한',
            isHighlighted: hasPenalty,
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required Color bg,
    required String title,
    required String description,
    required bool isHighlighted,
  }) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        // [DU265] 아이콘색 알파 10% → 의미 토큰 면(successBg/errorBg)
        color: isHighlighted ? bg : Colors.transparent,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 8),
        ),
        border: isHighlighted
            ? Border.all(color: iconColor.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: iconColor,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // [DU265] 낱말 단위 줄바꿈(B320 '전까/지'), 제목 본문색 명시
                Text(
                  TextLayout.keepWords(title),
                  semanticsLabel: title,
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  TextLayout.keepWords(description),
                  semanticsLabel: description,
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.textSecondary, // [DU265] grey600
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 현재 상태 + 경고
  // ═══════════════════════════════════════════════════════════

  Widget _buildCurrentStatus(BuildContext context, ThemeData theme) {
    final statusText = hasPenalty
        ? '현재 시점: 패널티 적용 구간'
        : '현재 시점: 패널티 없이 취소 가능';
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: hasPenalty ? AppColors.errorBg : AppColors.successBg,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.spacing(context, 12),
        ),
        border: Border.all(
          color: hasPenalty 
              ? AppColors.error.withValues(alpha: 0.3) 
              : AppColors.success.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 현재 시점 안내
          Row(
            children: [
              Icon(
                hasPenalty ? Icons.error : Icons.info,
                size: ResponsiveHelper.iconSize(context, 20),
                color: hasPenalty ? AppColors.errorDark : AppColors.successDark, // [DU265]
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: Text(
                  TextLayout.keepWords(statusText), // [DU265] B320 '패널/티' 끊김
                  semanticsLabel: statusText,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: hasPenalty ? AppColors.errorDark : AppColors.successDark,
                  ),
                ),
              ),
            ],
          ),
          
          if (hasPenalty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            
            // 경고 메시지
            Text(
              TextLayout.keepWords('이 취소는 패널티가 적용됩니다.'), // [DU265]
              semanticsLabel: '이 취소는 패널티가 적용됩니다.',
              style: ResponsiveHelper.bodyStyle(
                context,
                color: AppColors.errorDark,
              ),
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            
            // 현재 노쇼 횟수
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 10),
                vertical: ResponsiveHelper.spacing(context, 6),
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(
                  ResponsiveHelper.spacing(context, 8),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '노쇼 (최근 90일): ',
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
                    ),
                  ),
                  Text(
                    '$currentNoShowCount회',
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      // [DU265] error(3.68) → errorDark, 그 밖 본문색
                      color: currentNoShowCount >= 2 ? AppColors.errorDark : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    ' / 3회',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary), // [DU265] grey500(2.68)
                  ),
                  if (currentNoShowCount >= 2) ...[
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 6),
                        vertical: ResponsiveHelper.spacing(context, 2),
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.errorDark, // [DU265] 흰 글자 3.68 → 약 6.6
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '주의',
                        style: ResponsiveHelper.tinyStyle(context, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // 3회 도달 경고 — 정확히 2회일 때만 표시 (이미 3회 이상이면 제한 이미 적용됨)
            if (currentNoShowCount == 2) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Text(
                TextLayout.keepWords('⚠️ 이 취소 후 90일 기준 3회가 되어 1일간 지원이 제한됩니다!'), // [DU265]
                semanticsLabel: '⚠️ 이 취소 후 90일 기준 3회가 되어 1일간 지원이 제한됩니다!',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.errorDark, // [DU265] error(3.68)
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}