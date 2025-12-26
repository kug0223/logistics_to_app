// lib/widgets/dialogs/trust_score_info_dialog.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import 'styled_dialog.dart';

/// 신뢰도 점수 설명 다이얼로그
/// 
/// 사용법:
/// ```dart
/// TrustScoreInfoDialog.show(context);
/// ```
class TrustScoreInfoDialog extends StatelessWidget {
  const TrustScoreInfoDialog({super.key});

  /// 다이얼로그 표시
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const TrustScoreInfoDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return StyledDialog(
      title: '신뢰도 점수란?',
      subtitle: null,
      icon: Icons.info_outline,
      headerColor: theme.primaryColor,
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 설명
            _buildDescription(context),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
            
            // 올라가는 경우
            _buildIncreaseSection(context),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 내려가는 경우
            _buildDecreaseSection(context),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
            
            // 등급 배지
            _buildGradeSection(context),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
            
            // 팁
            _buildTipSection(context),
          ],
        ),
      ),
      actions: [
        StyledDialogButton.primary(
          text: '알겠어요!',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  /// 설명 섹션
  Widget _buildDescription(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.analytics_outlined,
            size: ResponsiveHelper.iconSize(context, 32),
            color: AppColors.infoDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              '신뢰도는 근태와 평가를 기반으로\n계산되는 점수입니다. (0~100점)',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: AppColors.infoDark,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 올라가는 경우 섹션
  Widget _buildIncreaseSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.arrow_upward,
              size: ResponsiveHelper.iconSize(context, 20),
              color: AppColors.success,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              '올라가는 경우',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.success,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildRuleItem(
          context,
          emoji: '✅',
          text: '정상 출퇴근',
          points: '+1점',
          pointColor: AppColors.success,
        ),
        _buildRuleItem(
          context,
          emoji: '⭐',
          text: '좋은 평가 (4.5점 이상)',
          points: '+2점',
          pointColor: AppColors.success,
        ),
        _buildRuleItem(
          context,
          emoji: '👍',
          text: '재고용 희망 받음',
          points: '+1점',
          pointColor: AppColors.success,
        ),
      ],
    );
  }

  /// 내려가는 경우 섹션
  Widget _buildDecreaseSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.arrow_downward,
              size: ResponsiveHelper.iconSize(context, 20),
              color: AppColors.error,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              '내려가는 경우',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildRuleItem(
          context,
          emoji: '⏰',
          text: '지각',
          points: '-1점',
          pointColor: AppColors.warning,
        ),
        _buildRuleItem(
          context,
          emoji: '🚫',
          text: '노쇼 (무단 결근)',
          points: '-3~10점',
          pointColor: AppColors.error,
          subText: '누적 횟수에 따라 증가',
        ),
        _buildRuleItem(
          context,
          emoji: '📉',
          text: '낮은 평가 (2.0점 이하)',
          points: '-2점',
          pointColor: AppColors.error,
        ),
      ],
    );
  }

  /// 등급 배지 섹션
  Widget _buildGradeSection(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.emoji_events,
              size: ResponsiveHelper.iconSize(context, 20),
              color: Colors.amber,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              '등급 배지',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: theme.primaryColor.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.primaryColor.withOpacity(0.2),
            ),
          ),
          child: Column(
            children: [
              _buildGradeRow(context, '🥉', '브론즈', '60점 이상'),
              Divider(height: ResponsiveHelper.spacing(context, 16)),
              _buildGradeRow(context, '🥈', '실버', '75점 이상'),
              Divider(height: ResponsiveHelper.spacing(context, 16)),
              _buildGradeRow(context, '🥇', '골드', '90점 이상'),
              Divider(height: ResponsiveHelper.spacing(context, 16)),
              _buildGradeRow(context, '💎', '다이아', '95점 이상 + 100일 근무'),
            ],
          ),
        ),
      ],
    );
  }

  /// 팁 섹션
  Widget _buildTipSection(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            '💡',
            style: TextStyle(fontSize: ResponsiveHelper.spacing(context, 24)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              '꾸준히 성실하게 근무하면\n신뢰도가 올라갑니다!',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: AppColors.warningDark,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 규칙 항목
  Widget _buildRuleItem(
    BuildContext context, {
    required String emoji,
    required String text,
    required String points,
    required Color pointColor,
    String? subText,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      child: Row(
        children: [
          Text(
            emoji,
            style: TextStyle(fontSize: ResponsiveHelper.spacing(context, 18)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: ResponsiveHelper.bodyStyle(context),
                ),
                if (subText != null)
                  Text(
                    subText,
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                  ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 10),
              vertical: ResponsiveHelper.spacing(context, 4),
            ),
            decoration: BoxDecoration(
              color: pointColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              points,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: pointColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 등급 행
  Widget _buildGradeRow(
    BuildContext context,
    String emoji,
    String name,
    String condition,
  ) {
    return Row(
      children: [
        Text(
          emoji,
          style: TextStyle(fontSize: ResponsiveHelper.spacing(context, 22)),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Text(
          name,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        Text(
          condition,
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        ),
      ],
    );
  }
}