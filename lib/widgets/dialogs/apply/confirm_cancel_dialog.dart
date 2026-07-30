// lib/widgets/dialogs/apply/confirm_cancel_dialog.dart

import 'package:flutter/material.dart';
import '../../../../utils/format_helper.dart';
import '../../../../utils/responsive_helper.dart';
import '../../../../theme/app_colors.dart';
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
  
  /// 패널티 적용 여부 (당일 취소)
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
  static Future<ConfirmCancelResult?> show({
    required BuildContext context,
    required DateTime workDate,
    required String workType,
    required String timeRange,
    required String businessName,
    required int currentNoShowCount,
  }) async {
    // 패널티 여부 계산
    final now = DateTime.now();
    final workDay = DateTime(workDate.year, workDate.month, workDate.day);
    final today = DateTime(now.year, now.month, now.day);
    final hasPenalty = workDay.isAtSameMomentAs(today) || workDay.isBefore(today);

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
      title: '확정 취소 안내',
      icon: Icons.warning_amber_rounded,
      headerColor: AppColors.error,
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
          backgroundColor: AppColors.error,
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
          Text(
            businessName,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 날짜 + 업무명
          Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.grey600,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                FormatHelper.formatDate(workDate),
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              Icon(
                Icons.work_outline,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.grey600,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Flexible(
                child: Text(
                  workType,
                  overflow: TextOverflow.ellipsis,
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
                ),
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
                color: AppColors.grey600,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                timeRange,
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
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
            iconColor: AppColors.success,
            title: '근무 1일 전까지',
            description: '패널티 없음',
            isHighlighted: !hasPenalty,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          
          // 당일 취소
          _buildPolicyItem(
            context,
            icon: Icons.warning,
            iconColor: AppColors.error,
            title: '당일 취소',
            description: '노쇼 1회 기록\n→ 3회 누적 시 3일 이용 제한',
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
    required String title,
    required String description,
    required bool isHighlighted,
  }) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: isHighlighted 
            ? iconColor.withValues(alpha: 0.1)
            : Colors.transparent,
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
                Text(
                  title,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  description,
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.grey600,
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
                color: hasPenalty ? AppColors.error : AppColors.success,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: Text(
                  hasPenalty 
                      ? '현재 시점: 당일 취소에 해당'
                      : '현재 시점: 패널티 없이 취소 가능',
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
              '이 취소는 패널티가 적용됩니다.',
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
                      '현재 노쇼 횟수: ',
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
                    ),
                  ),
                  Text(
                    '$currentNoShowCount회',
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: currentNoShowCount >= 2 ? AppColors.error : AppColors.grey700,
                    ),
                  ),
                  Text(
                    ' / 3회',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                  ),
                  if (currentNoShowCount >= 2) ...[
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 6),
                        vertical: ResponsiveHelper.spacing(context, 2),
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
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
                '⚠️ 이 취소 후 3회가 되어 3일간 이용이 제한됩니다!',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}