// lib/widgets/dialogs/trust_score_info_dialog.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/settings/trust_settings_model.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import 'styled_dialog.dart';

class _DialogData {
  final TrustSettingsModel settings;
  final List<BadgeModel> badges;
  const _DialogData({required this.settings, required this.badges});
}

/// 신뢰도 점수 설명 다이얼로그 — Firestore settings/trust_rules + badges 컬렉션 동기화
class TrustScoreInfoDialog extends StatefulWidget {
  const TrustScoreInfoDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const TrustScoreInfoDialog(),
    );
  }

  @override
  State<TrustScoreInfoDialog> createState() => _TrustScoreInfoDialogState();
}

class _TrustScoreInfoDialogState extends State<TrustScoreInfoDialog> {
  late final Future<_DialogData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  Future<_DialogData> _loadData() async {
    final results = await Future.wait([_fetchSettings(), _fetchBadges()]);
    return _DialogData(
      settings: results[0] as TrustSettingsModel,
      badges: results[1] as List<BadgeModel>,
    );
  }

  Future<TrustSettingsModel> _fetchSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('trust_rules')
          .get();
      return doc.exists
          ? TrustSettingsModel.fromFirestore(doc)
          : TrustSettingsModel.defaults();
    } catch (_) {
      return TrustSettingsModel.defaults();
    }
  }

  Future<List<BadgeModel>> _fetchBadges() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('badges')
          .where('isActive', isEqualTo: true)
          .orderBy('order')
          .get();
      final parsed = snap.docs.map((d) {
        try {
          return BadgeModel.fromMap(d.data(), d.id);
        } catch (_) {
          return null;
        }
      }).whereType<BadgeModel>().toList();
      return parsed.isEmpty ? BadgeModel.defaultBadges() : parsed;
    } catch (_) {
      return BadgeModel.defaultBadges();
    }
  }

  // 규칙 목록에서 type 매칭 포인트 조회 (없으면 fallback)
  int _rulePoints(List<TrustRule> rules, String type, int fallback) {
    return rules
        .firstWhere(
          (r) => r.type == type,
          orElse: () => TrustRule(type: type, points: fallback, description: ''),
        )
        .points;
  }

  // BadgeModel 필드에서 인간 가독형 조건 텍스트 생성
  String _conditionText(BadgeModel badge) {
    final parts = <String>[];
    switch (badge.conditionType) {
      case BadgeConditionType.minScore:
        parts.add('신뢰도 ${badge.conditionValue}점');
      case BadgeConditionType.workDays:
        parts.add('${badge.conditionValue}일 이상 근무');
      case BadgeConditionType.consecutive:
        parts.add('지각 없이 ${badge.conditionValue}회 연속 근무');
      case BadgeConditionType.monthlyPerfect:
        parts.add('퍼펙트 출근 ${badge.conditionValue}회 달성');
      case BadgeConditionType.sameBusinessRehire:
        parts.add('같은 사업장 ${badge.conditionValue}회 이상 재고용');
      case BadgeConditionType.uniqueBusinesses:
        parts.add('${badge.conditionValue}개 이상 다른 사업장 근무');
      case BadgeConditionType.nightShiftCount:
        parts.add('야간(22시 이후) 출근 ${badge.conditionValue}회 이상');
      case BadgeConditionType.earlyBirdCount:
        parts.add('새벽(6시 이전) 출근 ${badge.conditionValue}회 이상');
      case BadgeConditionType.weekendCount:
        parts.add('주말·공휴일 근무 ${badge.conditionValue}회 이상');
    }
    if (badge.minWorkDaysRequired != null) parts.add('근무 ${badge.minWorkDaysRequired}일+');
    if (badge.maxNoShowAllowed == 0) {
      parts.add('노쇼 없음');
    } else if (badge.maxNoShowAllowed != null) {
      parts.add('노쇼 ${badge.maxNoShowAllowed}회 이하');
    }
    if (badge.minRatingRequired != null) {
      parts.add('평점 ${badge.minRatingRequired!.toStringAsFixed(1)}+');
    }
    return parts.join(' · ');
  }

  // BadgeType별 섹션 스타일 (제목·색상)
  ({String title, Color titleColor, Color bgColor, Color borderColor})
      _badgeTypeStyle(BuildContext context, BadgeType type) {
    final theme = Theme.of(context);
    return switch (type) {
      BadgeType.trustScore => (
        title: '🏆 신뢰도 등급 배지',
        titleColor: AppColors.amber,
        bgColor: theme.primaryColor.withValues(alpha: 0.05),
        borderColor: theme.primaryColor.withValues(alpha: 0.2),
      ),
      BadgeType.experience => (
        title: '⭐ 경험 배지',
        titleColor: AppColors.purple,
        bgColor: AppColors.purple.withValues(alpha: 0.05),
        borderColor: AppColors.purple.withValues(alpha: 0.2),
      ),
      BadgeType.attendance => (
        title: '⏰ 근태 배지',
        titleColor: AppColors.success,
        bgColor: AppColors.success.withValues(alpha: 0.05),
        borderColor: AppColors.success.withValues(alpha: 0.2),
      ),
      BadgeType.specialty => (
        title: '🎮 도전 배지',
        titleColor: AppColors.info,
        bgColor: AppColors.info.withValues(alpha: 0.05),
        borderColor: AppColors.info.withValues(alpha: 0.2),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StyledDialog(
      title: '신뢰도 점수란?',
      subtitle: null,
      icon: Icons.info_outline,
      headerColor: theme.primaryColor,
      fillHeight: true,
      content: FutureBuilder<_DialogData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(color: theme.primaryColor),
            );
          }
          final data = snapshot.data!;
          return SingleChildScrollView(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDescription(context, data.settings),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                _buildIncreaseSection(context, data.settings),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                _buildDecreaseSection(context, data.settings),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                _buildNoShowPolicySection(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                _buildBadgeSection(context, data.badges),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                _buildTipSection(context),
              ],
            ),
          );
        },
      ),
      actions: [
        StyledDialogButton.primary(
          text: '알겠어요!',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  // ── 섹션 빌더 ──────────────────────────────────────────────────

  Widget _buildDescription(BuildContext context, TrustSettingsModel settings) {
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
              '신뢰도는 근무 경험·평판·근태를 종합해\n계산되는 점수입니다. (0~${settings.maxScore}점)\n기본 시작점은 ${settings.startScore}점이에요.',
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

  Widget _buildIncreaseSection(BuildContext context, TrustSettingsModel settings) {
    // 라벨(description)만 Firestore에서 동적으로 읽음
    // 점수 값은 TrustScoreHelper 실제 공식 상수 그대로 사용 (rule.points는 실제 계산에 미사용)
    final workDesc = settings.increaseRules
        .firstWhere((r) => r.type == 'work_complete',
            orElse: () => TrustRule(type: 'work_complete', points: 1, description: '근무 경험 쌓기'))
        .description;
    final reviewDesc = settings.increaseRules
        .firstWhere((r) => r.type == 'good_review',
            orElse: () => TrustRule(type: 'good_review', points: 2, description: '좋은 평가 받기'))
        .description;
    final rehireDesc = settings.increaseRules
        .firstWhere((r) => r.type == 'rehire_yes',
            orElse: () => TrustRule(type: 'rehire_yes', points: 1, description: '재고용 희망 받기'))
        .description;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, Icons.arrow_upward, '올라가는 경우', AppColors.success),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        Container(
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.success.withValues(alpha: 0.18)),
          ),
          child: Column(
            children: [
              _buildRuleItem(
                context,
                emoji: '📅',
                text: workDesc,
                points: '+4~+15점',
                pointColor: AppColors.success,
                subText: '10일↑: +4 / 20일↑: +8 / 40일↑: +12 / 60일↑: +15',
              ),
              const Divider(height: 1, indent: 44, color: AppColors.grey100),
              _buildRuleItem(
                context,
                emoji: '⭐',
                text: reviewDesc,
                points: '최대 +20점',
                pointColor: AppColors.success,
                subText: '평점 3.0 기준, 리뷰 5개 이상이면 풀반영',
              ),
              const Divider(height: 1, indent: 44, color: AppColors.grey100),
              _buildRuleItem(
                context,
                emoji: '👍',
                text: rehireDesc,
                points: '최대 +8점',
                pointColor: AppColors.success,
                subText: '리뷰 3개 이상일 때 반영',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDecreaseSection(BuildContext context, TrustSettingsModel settings) {
    final late1 = _rulePoints(settings.decreaseRules, 'late', -1);
    final late2 = _rulePoints(settings.decreaseRules, 'late_repeat', -2);
    final late3 = _rulePoints(settings.decreaseRules, 'late_chronic', -3);
    final noshow1 = settings.getNoshowPenalty(1);
    final noshow2 = settings.getNoshowPenalty(2);
    final noshow3 = settings.getNoshowPenalty(3);
    final badReview = _rulePoints(settings.decreaseRules, 'bad_review', -2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, Icons.arrow_downward, '내려가는 경우', AppColors.error),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        Container(
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              _buildRuleItem(
                context,
                emoji: '⏰',
                text: '지각',
                points: '$late1~$late3점/회',
                pointColor: AppColors.warning,
                subText: '1~2회: $late1점/회 · 3~5회: $late2점/회 · 6회+: $late3점/회',
              ),
              const Divider(height: 1, indent: 44, color: AppColors.grey100),
              _buildRuleItem(
                context,
                emoji: '🚫',
                text: '노쇼 (무단 결근)',
                points: '$noshow1~$noshow3점',
                pointColor: AppColors.error,
                subText: '1회: $noshow1점 · 2회: $noshow2점 · 3회+: $noshow3점씩 누진',
              ),
              const Divider(height: 1, indent: 44, color: AppColors.grey100),
              _buildRuleItem(
                context,
                emoji: '📉',
                text: '낮은 평가',
                points: '최대 $badReview점',
                pointColor: AppColors.error,
                subText: '평점 3.0 미만 시 감점 (리뷰 비례)',
              ),
            ],
          ),
        ),
      ],
    );
  }

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
              _buildPolicyRow(context, '1~2회 (90일 기준)', '신뢰도 감점만'),
              Divider(height: ResponsiveHelper.spacing(context, 14)),
              _buildPolicyRow(context, '3회 이상 (90일 기준)', '노쇼 발생 시마다 1일 지원 제한', isWarning: true),
            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Text(
          '※ 90일이 지나면 해당 노쇼는 자동으로 카운트에서 제외됩니다.',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(
          '※ 채용 여부는 사업장 관리자가 신뢰도·평판을 보고 판단합니다.',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        ),
      ],
    );
  }

  Widget _buildBadgeSection(BuildContext context, List<BadgeModel> badges) {
    // BadgeType 표시 순서
    final orderedTypes = [
      BadgeType.trustScore,
      BadgeType.experience,
      BadgeType.attendance,
      BadgeType.specialty,
    ];

    final grouped = {
      for (final t in orderedTypes)
        t: badges.where((b) => b.type == t).toList(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, Icons.emoji_events, '달성 배지 안내', AppColors.amber),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        for (final type in orderedTypes)
          if (grouped[type]!.isNotEmpty) ...[
            _buildBadgeSubSection(context, type, grouped[type]!),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ],
      ],
    );
  }

  Widget _buildBadgeSubSection(
    BuildContext context,
    BadgeType type,
    List<BadgeModel> badges,
  ) {
    final style = _badgeTypeStyle(context, type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: ResponsiveHelper.spacing(context, 2),
            bottom: ResponsiveHelper.spacing(context, 8),
          ),
          child: Text(
            style.title,
            style: ResponsiveHelper.smallStyle(context, color: style.titleColor)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: style.bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: style.borderColor),
          ),
          child: Column(
            children: [
              for (int i = 0; i < badges.length; i++) ...[
                if (i > 0) Divider(height: ResponsiveHelper.spacing(context, 14)),
                _buildBadgeRow(
                  context,
                  badge: badges[i],
                  condition: _conditionText(badges[i]),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

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
              '노쇼 없이 꾸준히 근무하면 신뢰도가 올라가고\n더 많은 TO에 우선 지원이 가능해요!\n이용 제한은 최근 90일 3회부터 적용돼요.',
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

  // ── 공통 위젯 ───────────────────────────────────────────────────

  Widget _buildSectionHeader(BuildContext context, IconData icon, String title, Color color) {
    return Row(
      children: [
        Container(
          width: 3,
          height: ResponsiveHelper.spacing(context, 20),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Icon(icon, size: ResponsiveHelper.iconSize(context, 17), color: color),
        SizedBox(width: ResponsiveHelper.spacing(context, 5)),
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

  Widget _buildPolicyRow(BuildContext context, String label, String value,
      {bool isWarning = false}) {
    final color = isWarning ? AppColors.error : AppColors.errorDark;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w500),
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
            style: ResponsiveHelper.smallStyle(context, color: color)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildRuleItem(
    BuildContext context, {
    required String emoji,
    required String text,
    required String points,
    required Color pointColor,
    String? subText,
  }) {
    final emojiSize = ResponsiveHelper.getScale(context) * 14.0;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이모지: 고정 너비로 정렬 통일
          SizedBox(
            width: ResponsiveHelper.spacing(context, 22),
            child: Text(
              emoji,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: emojiSize, height: 1.4),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 제목 + 뱃지 (같은 행, 뱃지는 minWidth 고정)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        text,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.grey800,
                        ),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 74),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 8),
                          vertical: ResponsiveHelper.spacing(context, 3),
                        ),
                        decoration: BoxDecoration(
                          color: pointColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          points,
                          textAlign: TextAlign.center,
                          style: ResponsiveHelper.tinyStyle(context, color: pointColor)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
                // 설명: 전체 너비, 한 단계 작게
                if (subText != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                  Text(
                    subText,
                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeRow(
    BuildContext context, {
    required BadgeModel badge,
    required String condition,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          badge.icon,
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
                badge.name,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.grey800,
                ),
              ),
              Text(
                condition,
                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
              ),
              if (badge.benefit != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '✓ ',
                      style: ResponsiveHelper.tinyStyle(context, color: AppColors.amberDark)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Text(
                        badge.benefit!,
                        style: ResponsiveHelper.tinyStyle(context, color: AppColors.amberDark),
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
