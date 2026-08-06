// lib/widgets/common/badge_display_widget.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../../models/settings/trust_settings_model.dart';
import '../../providers/badge_provider.dart';
import '../../widgets/dialogs/styled_dialog.dart';

// ── 파일 공용 헬퍼 ────────────────────────────────────────────────

/// BadgeType → 베이스 색상
Color _badgeColor(BadgeType type) {
  switch (type) {
    case BadgeType.trustScore: return AppColors.amber;
    case BadgeType.attendance: return AppColors.success;
    case BadgeType.experience: return AppColors.purple;
    case BadgeType.specialty:  return AppColors.info;
  }
}

/// BadgeType → 그라데이션 색상 (상단 밝음 → 하단 진함)
List<Color> _badgeGradient(BadgeType type) {
  switch (type) {
    case BadgeType.trustScore:
      return [const Color(0xFFFFCA28), const Color(0xFFE65100)]; // amber-deep-orange
    case BadgeType.attendance:
      return [const Color(0xFF66BB6A), const Color(0xFF1B5E20)]; // green
    case BadgeType.experience:
      return [const Color(0xFFBA68C8), const Color(0xFF6A1B9A)]; // purple
    case BadgeType.specialty:
      return [const Color(0xFF42A5F5), const Color(0xFF0D47A1)]; // blue
  }
}

// ── BadgeDisplayWidget ────────────────────────────────────────────

/// 획득 배지 표시 위젯 — 수평 Wrap 레이아웃
class BadgeDisplayWidget extends StatelessWidget {
  final List<String> badgeIds;
  final int? maxDisplay;
  final bool compact;
  final bool clickable;

  const BadgeDisplayWidget({
    super.key,
    required this.badgeIds,
    this.maxDisplay,
    this.compact = false,
    this.clickable = true,
  });

  @override
  Widget build(BuildContext context) {
    if (badgeIds.isEmpty) return _buildEmptyState(context);

    final allBadges = context.watch<BadgeProvider>().badges;

    // allEarned: 획득 전체 — AllBadgesDialog에 전달 (필터 없음)
    final allEarned = allBadges
        .where((b) => badgeIds.contains(b.id))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // BadgeProvider 로딩 중 또는 유효하지 않은 ID만 있을 때 empty state 표시
    if (allEarned.isEmpty) return _buildEmptyState(context);

    // rowEarned: 압축 행 전용 — 등급/경험 계열은 최고 단계 하나만 표시
    final rowEarned = List<BadgeModel>.from(allEarned);

    // 신뢰도 배지: 최고 등급만 (diamond > gold > silver > bronze)
    const trustIds = ['badge_diamond', 'badge_gold', 'badge_silver', 'badge_bronze'];
    final earnedTrustIds = rowEarned.map((b) => b.id).where(trustIds.contains).toSet();
    if (earnedTrustIds.length > 1) {
      final highest = trustIds.firstWhere(earnedTrustIds.contains);
      rowEarned.removeWhere((b) => trustIds.contains(b.id) && b.id != highest);
    }

    // 경험 배지: 최고 단계만 (master > veteran > experienced > growing > first_step)
    const expIds = ['badge_master', 'badge_veteran', 'badge_experienced', 'badge_growing', 'badge_first_step'];
    final earnedExpIds = rowEarned.map((b) => b.id).where(expIds.contains).toSet();
    if (earnedExpIds.length > 1) {
      final highestExp = expIds.firstWhere(earnedExpIds.contains);
      rowEarned.removeWhere((b) => expIds.contains(b.id) && b.id != highestExp);
    }

    final display = (maxDisplay != null && rowEarned.length > maxDisplay!)
        ? rowEarned.take(maxDisplay!).toList()
        : rowEarned;
    final remaining = rowEarned.length - display.length;

    return Wrap(
      spacing: ResponsiveHelper.spacing(context, compact ? 6 : 8),
      runSpacing: ResponsiveHelper.spacing(context, compact ? 6 : 8),
      children: [
        ...display.map((b) => _buildBadgeChip(context, b)),
        if (remaining > 0) _buildMoreChip(context, remaining, allEarned),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: ResponsiveHelper.iconSize(context, compact ? 14 : 16),
            color: AppColors.grey400,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text(
            '아직 획득한 배지가 없습니다',
            style: compact
                ? ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)
                : ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeChip(BuildContext context, BadgeModel badge) {
    final size = compact ? 32.0 : 40.0;
    final color = _badgeColor(badge.type);
    final gradient = _badgeGradient(badge.type);
    final emojiSize = compact
        ? ResponsiveHelper.bodyStyle(context).fontSize!
        : ResponsiveHelper.subtitleStyle(context).fontSize! * 1.1;

    return GestureDetector(
      onTap: clickable ? () => _showBadgeDetail(context, badge) : null,
      child: Tooltip(
        message: badge.name,
        child: Container(
          width: ResponsiveHelper.spacing(context, size),
          height: ResponsiveHelper.spacing(context, size),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.45),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              badge.icon,
              style: TextStyle(fontSize: emojiSize),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoreChip(BuildContext context, int count, List<BadgeModel> all) {
    final size = compact ? 32.0 : 40.0;
    return GestureDetector(
      onTap: clickable ? () => _showAllBadges(context, all) : null,
      child: Container(
        width: ResponsiveHelper.spacing(context, size),
        height: ResponsiveHelper.spacing(context, size),
        decoration: BoxDecoration(
          color: AppColors.grey200,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            '+$count',
            style: (compact
                    ? ResponsiveHelper.tinyStyle(context, color: AppColors.grey600)
                    : ResponsiveHelper.smallStyle(context, color: AppColors.grey600))
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  void _showBadgeDetail(BuildContext context, BadgeModel badge) {
    showDialog(context: context, builder: (_) => BadgeDetailDialog(badge: badge));
  }

  void _showAllBadges(BuildContext context, List<BadgeModel> badges) {
    showDialog(context: context, builder: (_) => AllBadgesDialog(badges: badges));
  }
}

// ── BadgeDetailDialog ─────────────────────────────────────────────

/// 배지 상세 다이얼로그
class BadgeDetailDialog extends StatelessWidget {
  final BadgeModel badge;
  const BadgeDetailDialog({super.key, required this.badge});

  @override
  Widget build(BuildContext context) {
    final color = _badgeColor(badge.type);
    final gradient = _badgeGradient(badge.type);
    final iconSize = ResponsiveHelper.spacing(context, 92);

    return StyledDialog(
      title: badge.name,
      subtitle: _typeLabel(badge.type),
      icon: Icons.emoji_events,
      headerColor: color,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 대형 배지 아이콘 (그라데이션 + 광택 오버레이 + 발광) ──
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.50),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 40,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipOval(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 상단 광택 레이어
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: iconSize * 0.45,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.28),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 이모지
                  Text(
                    badge.icon,
                    style: TextStyle(
                      fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 2.2,
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 20)),

          // ── 획득 조건 ──
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: AppColors.success),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      '획득 조건',
                      style: ResponsiveHelper.bodyStyle(context)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Text(
                  _conditionText(badge),
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
                ),
              ],
            ),
          ),

          // ── 혜택 ──
          if (badge.benefit != null && badge.benefit!.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.card_giftcard,
                          size: ResponsiveHelper.iconSize(context, 18),
                          color: AppColors.amber),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        '배지 혜택',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.amber,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  ...badge.benefit!.split(' · ').map(
                    (item) => Padding(
                      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 4)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '✓ ',
                            style: ResponsiveHelper.bodyStyle(context, color: AppColors.amber)
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                          Expanded(
                            child: Text(
                              item,
                              style: ResponsiveHelper.bodyStyle(context,
                                  color: AppColors.grey700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        StyledDialogButton.primary(
          text: '확인',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  String _typeLabel(BadgeType type) {
    switch (type) {
      case BadgeType.trustScore: return '신뢰도 배지';
      case BadgeType.attendance: return '근태 배지';
      case BadgeType.experience: return '경험 배지';
      case BadgeType.specialty:  return '도전 배지';
    }
  }

  String _conditionText(BadgeModel badge) {
    final parts = <String>[];
    switch (badge.conditionType) {
      case BadgeConditionType.minScore:
        parts.add('신뢰도 ${badge.conditionValue}점 이상 달성');
      case BadgeConditionType.workDays:
        parts.add('총 ${badge.conditionValue}일 이상 근무');
      case BadgeConditionType.consecutive:
        parts.add('지각 없이 ${badge.conditionValue}회 연속 정상 출근');
      case BadgeConditionType.monthlyPerfect:
        parts.add('한 달 신청 공고 100% 출근');
      case BadgeConditionType.nightShiftCount:
        parts.add('야간(22시 이후) 출근 ${badge.conditionValue}회 달성');
      case BadgeConditionType.earlyBirdCount:
        parts.add('새벽(6시 이전) 출근 ${badge.conditionValue}회 달성');
      case BadgeConditionType.weekendCount:
        parts.add('주말·공휴일 근무 ${badge.conditionValue}회 달성');
      case BadgeConditionType.sameBusinessRehire:
        parts.add('같은 사업장 ${badge.conditionValue}회 이상 재고용');
      case BadgeConditionType.uniqueBusinesses:
        parts.add('${badge.conditionValue}개 이상 다른 사업장 근무');
    }
    if (badge.minWorkDaysRequired != null) parts.add('추가 근무 ${badge.minWorkDaysRequired}일+');
    if (badge.maxNoShowAllowed == 0) {
      parts.add('노쇼 0회');
    } else if (badge.maxNoShowAllowed != null) {
      parts.add('노쇼 ${badge.maxNoShowAllowed}회 이하');
    }
    if (badge.minRatingRequired != null) {
      parts.add('평점 ${badge.minRatingRequired!.toStringAsFixed(1)} 이상');
    }
    return parts.join('\n');
  }

}

// ── AllBadgesDialog ───────────────────────────────────────────────

/// 전체 획득 배지 다이얼로그
class AllBadgesDialog extends StatelessWidget {
  final List<BadgeModel> badges;
  const AllBadgesDialog({super.key, required this.badges});

  @override
  Widget build(BuildContext context) {
    final groups = <BadgeType, List<BadgeModel>>{
      BadgeType.trustScore: badges.where((b) => b.type == BadgeType.trustScore).toList(),
      BadgeType.experience: badges.where((b) => b.type == BadgeType.experience).toList(),
      BadgeType.attendance: badges.where((b) => b.type == BadgeType.attendance).toList(),
      BadgeType.specialty:  badges.where((b) => b.type == BadgeType.specialty).toList(),
    };
    final sectionOrder = [
      BadgeType.trustScore,
      BadgeType.experience,
      BadgeType.attendance,
      BadgeType.specialty,
    ];
    final sectionTitles = {
      BadgeType.trustScore: '🏆 신뢰도 배지',
      BadgeType.experience: '⭐ 경험 배지',
      BadgeType.attendance: '⏰ 근태 배지',
      BadgeType.specialty:  '📦 전문 배지',
    };

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: AppDialogSize.insetV,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.emoji_events,
                      color: Colors.white,
                      size: ResponsiveHelper.iconSize(context, 24)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Text(
                    '획득한 배지 (${badges.length}개)',
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // 내용
            Flexible(
              child: SingleChildScrollView(
                padding: ResponsiveHelper.cardPadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final type in sectionOrder)
                      if (groups[type]!.isNotEmpty) ...[
                        _buildSection(context, sectionTitles[type]!, type, groups[type]!),
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    BadgeType type,
    List<BadgeModel> sectionBadges,
  ) {
    final color = _badgeColor(type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: ResponsiveHelper.subtitleStyle(context)
              .copyWith(fontWeight: FontWeight.bold, color: color),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        Wrap(
          spacing: ResponsiveHelper.spacing(context, 10),
          runSpacing: ResponsiveHelper.spacing(context, 10),
          children: sectionBadges.map((b) => _buildBadgeCard(context, b)).toList(),
        ),
      ],
    );
  }

  Widget _buildBadgeCard(BuildContext context, BadgeModel badge) {
    final color = _badgeColor(badge.type);
    final gradient = _badgeGradient(badge.type);
    final chipSize = ResponsiveHelper.spacing(context, 48);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        if (context.mounted) {
          showDialog(context: context, builder: (_) => BadgeDetailDialog(badge: badge));
        }
      },
      child: Container(
        width: ResponsiveHelper.spacing(context, 74),
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // 그라데이션 원형 배지
            Container(
              width: chipSize,
              height: chipSize,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.30),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  badge.icon,
                  style: TextStyle(
                    fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 1.2,
                  ),
                ),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                badge.name,
                style: ResponsiveHelper.tinyStyle(context, color: color)
                    .copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
