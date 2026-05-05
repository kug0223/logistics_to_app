// lib/widgets/common/badge_display_widget.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../../models/settings/trust_settings_model.dart';
import '../../widgets/dialogs/styled_dialog.dart';

/// 배지 표시 위젯
/// 
/// 사용자의 획득한 배지를 표시합니다.
class BadgeDisplayWidget extends StatelessWidget {
  /// 획득한 배지 ID 목록
  final List<String> badgeIds;
  
  /// 최대 표시 개수 (null이면 전체)
  final int? maxDisplay;
  
  /// 컴팩트 모드 (작은 크기)
  final bool compact;
  
  /// 배지 클릭 가능 여부
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
    if (badgeIds.isEmpty) {
      return _buildEmptyState(context);
    }
    
    // 기본 배지 목록에서 획득한 배지 찾기
    final allBadges = BadgeModel.defaultBadges();
    final earnedBadges = allBadges
        .where((b) => badgeIds.contains(b.id))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    
    // 표시할 배지 수 제한
    final displayBadges = maxDisplay != null && earnedBadges.length > maxDisplay!
        ? earnedBadges.take(maxDisplay!).toList()
        : earnedBadges;
    
    final remainingCount = earnedBadges.length - displayBadges.length;
    
    return Wrap(
      spacing: ResponsiveHelper.spacing(context, compact ? 6 : 8),
      runSpacing: ResponsiveHelper.spacing(context, compact ? 6 : 8),
      children: [
        ...displayBadges.map((badge) => _buildBadgeChip(context, badge)),
        if (remainingCount > 0)
          _buildMoreChip(context, remainingCount, earnedBadges),
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
            style: (compact 
                ? ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)
                : ResponsiveHelper.smallStyle(context, color: AppColors.grey500)),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeChip(BuildContext context, BadgeModel badge) {
    final size = compact ? 28.0 : 36.0;
    
    return GestureDetector(
      onTap: clickable ? () => _showBadgeDetail(context, badge) : null,
      child: Tooltip(
        message: badge.name,
        child: Container(
          width: ResponsiveHelper.spacing(context, size),
          height: ResponsiveHelper.spacing(context, size),
          decoration: BoxDecoration(
            color: _getBadgeColor(badge.type).withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: _getBadgeColor(badge.type).withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              badge.icon,
              style: TextStyle(
                fontSize: ResponsiveHelper.spacing(context, compact ? 14 : 18),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoreChip(BuildContext context, int count, List<BadgeModel> allBadges) {
    final size = compact ? 28.0 : 36.0;
    
    return GestureDetector(
      onTap: clickable ? () => _showAllBadges(context, allBadges) : null,
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

  Color _getBadgeColor(BadgeType type) {
    switch (type) {
      case BadgeType.trustScore:
        return Colors.amber;
      case BadgeType.attendance:
        return AppColors.success;
      case BadgeType.specialty:
        return AppColors.info;
    }
  }

  void _showBadgeDetail(BuildContext context, BadgeModel badge) {
    showDialog(
      context: context,
      builder: (context) => BadgeDetailDialog(badge: badge),
    );
  }

  void _showAllBadges(BuildContext context, List<BadgeModel> badges) {
    showDialog(
      context: context,
      builder: (context) => AllBadgesDialog(badges: badges),
    );
  }
}

/// 배지 상세 다이얼로그
class BadgeDetailDialog extends StatelessWidget {
  final BadgeModel badge;

  const BadgeDetailDialog({super.key, required this.badge});

  @override
  Widget build(BuildContext context) {
    return StyledDialog(
      title: badge.name,
      subtitle: _getBadgeTypeText(badge.type),
      icon: Icons.emoji_events,
      headerColor: _getBadgeColor(badge.type),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 배지 아이콘 (대형)
          Container(
            width: ResponsiveHelper.spacing(context, 80),
            height: ResponsiveHelper.spacing(context, 80),
            decoration: BoxDecoration(
              color: _getBadgeColor(badge.type).withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: _getBadgeColor(badge.type).withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                badge.icon,
                style: TextStyle(fontSize: ResponsiveHelper.spacing(context, 40)),
              ),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
          
          // 획득 조건
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: ResponsiveHelper.iconSize(context, 18),
                      color: AppColors.success,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      '획득 조건',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Text(
                  _getConditionText(badge),
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
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

  String _getBadgeTypeText(BadgeType type) {
    switch (type) {
      case BadgeType.trustScore:
        return '신뢰도 배지';
      case BadgeType.attendance:
        return '근태 배지';
      case BadgeType.specialty:
        return '전문 배지';
    }
  }

  Color _getBadgeColor(BadgeType type) {
    switch (type) {
      case BadgeType.trustScore:
        return Colors.amber;
      case BadgeType.attendance:
        return AppColors.success;
      case BadgeType.specialty:
        return AppColors.info;
    }
  }

  String _getConditionText(BadgeModel badge) {
    switch (badge.conditionType) {
      case BadgeConditionType.minScore:
        return '신뢰도 ${badge.conditionValue}점 이상 달성';
      case BadgeConditionType.workDays:
        if (badge.workType != null) {
          return '${_getWorkTypeName(badge.workType!)} 업무 ${badge.conditionValue}일 이상 근무';
        }
        return '총 ${badge.conditionValue}일 이상 근무';
      case BadgeConditionType.consecutive:
        return '연속 ${badge.conditionValue}일 정상 출근';
      case BadgeConditionType.monthlyPerfect:
        return '${badge.conditionValue}개월 연속 100% 출근';
    }
  }

  String _getWorkTypeName(String workType) {
    switch (workType) {
      case 'PICK': return '피킹';
      case 'LOAD': return '상하차';
      case 'INSPECT': return '검수';
      case 'PACK': return '패킹';
      default: return workType;
    }
  }
}

/// 전체 배지 다이얼로그
class AllBadgesDialog extends StatelessWidget {
  final List<BadgeModel> badges;

  const AllBadgesDialog({super.key, required this.badges});

  @override
  Widget build(BuildContext context) {
    // 타입별 그룹화
    final trustBadges = badges.where((b) => b.type == BadgeType.trustScore).toList();
    final attendanceBadges = badges.where((b) => b.type == BadgeType.attendance).toList();
    final specialtyBadges = badges.where((b) => b.type == BadgeType.specialty).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.emoji_events,
                    color: Colors.white,
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Text(
                    '획득한 배지 (${badges.length}개)',
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: Colors.white),
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
                    if (trustBadges.isNotEmpty) ...[
                      _buildSection(context, '🏆 신뢰도 배지', trustBadges),
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                    ],
                    if (attendanceBadges.isNotEmpty) ...[
                      _buildSection(context, '⏰ 근태 배지', attendanceBadges),
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                    ],
                    if (specialtyBadges.isNotEmpty)
                      _buildSection(context, '📦 전문 배지', specialtyBadges),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<BadgeModel> badges) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Wrap(
          spacing: ResponsiveHelper.spacing(context, 12),
          runSpacing: ResponsiveHelper.spacing(context, 12),
          children: badges.map((badge) => _buildBadgeItem(context, badge)).toList(),
        ),
      ],
    );
  }

  Widget _buildBadgeItem(BuildContext context, BadgeModel badge) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => BadgeDetailDialog(badge: badge),
        );
      },
      child: Container(
        width: ResponsiveHelper.spacing(context, 70),
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.grey200),
        ),
        child: Column(
          children: [
            Text(
              badge.icon,
              style: TextStyle(fontSize: ResponsiveHelper.spacing(context, 28)),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              badge.name,
              style: ResponsiveHelper.tinyStyle(context),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}