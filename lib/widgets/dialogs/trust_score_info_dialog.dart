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

            // 노쇼 이용 제한 정책
            _buildNoShowPolicySection(context),

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
              '신뢰도는 근무 경험·평판·근태를 종합해\n계산되는 점수입니다. (0~100점)\n기본 시작점은 60점이에요.',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: AppColors.infoDark,
                height: 1.5,
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
        _buildSectionHeader(context, Icons.arrow_upward, '올라가는 경우', AppColors.success),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildRuleItem(
          context,
          emoji: '📅',
          text: '근무 경험 쌓기',
          points: '+4~+15점',
          pointColor: AppColors.success,
          subText: '10일↑: +4 / 20일↑: +8 / 40일↑: +12 / 60일↑: +15',
        ),
        _buildRuleItem(
          context,
          emoji: '⭐',
          text: '좋은 평가 받기',
          points: '최대 +20점',
          pointColor: AppColors.success,
          subText: '평점 3.0 기준, 리뷰 5개 이상이면 풀반영',
        ),
        _buildRuleItem(
          context,
          emoji: '👍',
          text: '재고용 희망 받기',
          points: '최대 +8점',
          pointColor: AppColors.success,
          subText: '리뷰 3개 이상일 때 반영',
        ),
      ],
    );
  }

  /// 내려가는 경우 섹션
  Widget _buildDecreaseSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, Icons.arrow_downward, '내려가는 경우', AppColors.error),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildRuleItem(
          context,
          emoji: '⏰',
          text: '지각',
          points: '-1~-3점',
          pointColor: AppColors.warning,
          subText: '1~2회: -1점/회 · 3~5회: -2점/회 · 6회+: -3점/회',
        ),
        _buildRuleItem(
          context,
          emoji: '🚫',
          text: '노쇼 (무단 결근)',
          points: '-5~-10점',
          pointColor: AppColors.error,
          subText: '1회: -5점 · 2회: -8점 · 3회+: -10점씩 누진',
        ),
        _buildRuleItem(
          context,
          emoji: '📉',
          text: '낮은 평가',
          points: '최대 -10점',
          pointColor: AppColors.error,
          subText: '평점 3.0 미만 시 감점 (리뷰 비례)',
        ),
      ],
    );
  }

  /// 노쇼 이용 제한 정책 섹션
  Widget _buildNoShowPolicySection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, Icons.block_rounded, '노쇼 이용 제한 정책', AppColors.error),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: AppColors.errorBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              _buildPolicyRow(context, '1회 노쇼', '3일 이용 제한'),
              Divider(height: ResponsiveHelper.spacing(context, 14)),
              _buildPolicyRow(context, '2회 노쇼', '7일 이용 제한'),
              Divider(height: ResponsiveHelper.spacing(context, 14)),
              _buildPolicyRow(context, '3회 노쇼', '30일 이용 제한'),
              Divider(height: ResponsiveHelper.spacing(context, 14)),
              _buildPolicyRow(context, '4회 이상', '영구 이용 제한', isWarning: true),
            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Text(
          '※ 장기간 성실히 근무한 경우 노쇼 감점이 최대 50% 경감될 수 있습니다.',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
        ),
      ],
    );
  }

  /// 달성 배지 안내 섹션
  Widget _buildGradeSection(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, Icons.emoji_events, '달성 배지 안내', AppColors.amber),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        // 신뢰도 등급 배지
        _buildBadgeSubSection(context, '🏆 신뢰도 등급 배지', AppColors.amber,
          theme.primaryColor.withValues(alpha: 0.05),
          theme.primaryColor.withValues(alpha: 0.2),
          [
            _buildBadgeRow(context, '🥉', '브론즈', '신뢰도 60점 + 근무 5일 이상',
              benefit: '신뢰도 인증 근무자로 관리자 목록에 배지 표시'),
            Divider(height: ResponsiveHelper.spacing(context, 14)),
            _buildBadgeRow(context, '🥈', '실버', '70점 + 20일 · 노쇼 1회 이하',
              benefit: '관리자 목록 강조 표시 · 신뢰도 검증 근무자로 우선 노출'),
            Divider(height: ResponsiveHelper.spacing(context, 14)),
            _buildBadgeRow(context, '🥇', '골드', '85점 + 50일 · 노쇼 없음',
              benefit: '자동확정 공고 지원 가능 · 재고용 시 우선 채팅 알림'),
            Divider(height: ResponsiveHelper.spacing(context, 14)),
            _buildBadgeRow(context, '💎', '다이아', '95점 + 100일 · 평점 4.5+ · 노쇼 없음',
              benefit: '자동확정 공고 우선 배정 · 단골 사업장 빠른 매칭 · 최고 등급 인증'),
          ],
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        // 경험 배지
        _buildBadgeSubSection(context, '⭐ 경험 배지', AppColors.purple,
          AppColors.purple.withValues(alpha: 0.05),
          AppColors.purple.withValues(alpha: 0.2),
          [
            _buildBadgeRow(context, '⭐', '베테랑', '총 근무 100일 이상',
              benefit: '100일 근무 경력 공식 인증 · 이력서에 경험 배지 표시'),
            Divider(height: ResponsiveHelper.spacing(context, 14)),
            _buildBadgeRow(context, '👑', '마스터', '총 근무 200일 이상',
              benefit: '200일 장기 근무 최고 경험 배지 · 플랫폼 최우수 경력자 인증'),
          ],
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        // 근태 배지
        _buildBadgeSubSection(context, '⏰ 근태 배지', AppColors.success,
          AppColors.success.withValues(alpha: 0.05),
          AppColors.success.withValues(alpha: 0.2),
          [
            _buildBadgeRow(context, '🔥', '연속 출근', '지각 없이 15회 연속 근무',
              benefit: '꾸준한 근무 습관 보유자 표시 · 성실 근태 인증'),
            Divider(height: ResponsiveHelper.spacing(context, 14)),
            _buildBadgeRow(context, '⏰', '시간의 달인', '지각 없이 30회 연속 근무',
              benefit: '정시 출근 전문가 공식 인증 · 지각 이력 무결 증명'),
            Divider(height: ResponsiveHelper.spacing(context, 14)),
            _buildBadgeRow(context, '🎯', '퍼펙트 출근', '한 달 신청 공고 100% 출근',
              benefit: '월간 만근 인증 · 성실 근무자 상징 배지'),
          ],
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        // 업종 배지
        _buildBadgeSubSection(context, '📦 업종 전문 배지', AppColors.info,
          AppColors.info.withValues(alpha: 0.05),
          AppColors.info.withValues(alpha: 0.2),
          [
            _buildBadgeRow(
              context, '📦', '피킹 전문가', '피킹 업무 30일 이상 근무',
              benefit: '피킹 업무 실력 공식 인증 · 동종 공고 우선 표시'),
            Divider(height: ResponsiveHelper.spacing(context, 14)),
            _buildBadgeRow(
              context, '🏋️', '상하차 전문가', '상하차 업무 30일 이상 근무',
              benefit: '상하차 업무 실력 공식 인증 · 동종 공고 우선 표시'),
            Divider(height: ResponsiveHelper.spacing(context, 14)),
            _buildBadgeRow(
              context, '🔍', '검수 전문가', '검수 업무 30일 이상 근무',
              benefit: '검수 업무 실력 공식 인증 · 꼼꼼한 품질 관리 역량 증명'),
          ],
        ),
      ],
    );
  }

  Widget _buildBadgeSubSection(
    BuildContext context,
    String title,
    Color titleColor,
    Color bgColor,
    Color borderColor,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 2), bottom: ResponsiveHelper.spacing(context, 8)),
          child: Text(
            title,
            style: ResponsiveHelper.smallStyle(context, color: titleColor).copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: Column(children: children),
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
          Text('💡', style: ResponsiveHelper.titleStyle(context)),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              '노쇼 없이 꾸준히 근무하면 신뢰도가 올라가고\n더 많은 TO에 우선 지원이 가능해져요!',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: AppColors.warningDark,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── private 공통 위젯 ──────────────────────────────────────────

  Widget _buildSectionHeader(BuildContext context, IconData icon, String title, Color color) {
    return Row(
      children: [
        Icon(icon, size: ResponsiveHelper.iconSize(context, 20), color: color),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Text(
          title,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildPolicyRow(BuildContext context, String label, String value, {bool isWarning = false}) {
    final color = isWarning ? AppColors.error : AppColors.errorDark;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 10),
            vertical: ResponsiveHelper.spacing(context, 4),
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: ResponsiveHelper.smallStyle(context, color: color).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
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
            style: ResponsiveHelper.subtitleStyle(context),
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
              color: pointColor.withValues(alpha: 0.1),
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

  /// 배지 행 (이름 + 달성 조건 + 혜택)
  Widget _buildBadgeRow(
    BuildContext context,
    String emoji,
    String name,
    String condition, {
    String? benefit,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          emoji,
          style: ResponsiveHelper.titleStyle(context).copyWith(
            fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 1.1,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                condition,
                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
              ),
              if (benefit != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '✓ ',
                      style: ResponsiveHelper.tinyStyle(context, color: AppColors.amber)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Text(
                        benefit,
                        style: ResponsiveHelper.tinyStyle(context, color: AppColors.amber),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}