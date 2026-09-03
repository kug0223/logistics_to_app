// lib/screens/user/my_activity_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/settings/trust_settings_model.dart';
import '../../providers/badge_provider.dart';
import '../../theme/app_colors.dart';

/// 나의 활동 — 획득 배지 전체 목록
///
/// 배지는 "등급 시스템"이 아니라 "근무 이력·성취 기록"이다.
/// 신뢰도(trustScore) 계열 배지는 이 화면에서 표시하지 않는다.
///
/// 카테고리:
///   근무  → BadgeType.experience  (근무 횟수·사업장 다양성)
///   출근  → BadgeType.attendance  (연속 출근·야간·주말)
///   경험  → BadgeType.specialty   (특별 성취)
class MyActivityScreen extends StatefulWidget {
  final List<String> userBadgeIds;
  const MyActivityScreen({super.key, required this.userBadgeIds});

  @override
  State<MyActivityScreen> createState() => _MyActivityScreenState();
}

class _MyActivityScreenState extends State<MyActivityScreen> {
  int _selectedTab = 0; // 0=전체, 1=근무, 2=출근, 3=경험

  static const _tabs = ['전체', '근무', '출근', '경험'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '나의 활동',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderLight),
        ),
      ),
      body: Consumer<BadgeProvider>(
        builder: (context, badgeProvider, _) {
          // trustScore 계열 배지 제외 — 신뢰도 점수 시스템 UI 제거 결정
          final allEarned = badgeProvider.badges
              .where((b) =>
                  widget.userBadgeIds.contains(b.id) &&
                  b.type != BadgeType.trustScore)
              .toList()
            ..sort((a, b) => a.order.compareTo(b.order));

          final filtered = _filter(allEarned);
          final grouped = _group(filtered);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 요약 헤더 ─────────────────────────────────────
              _buildHeader(allEarned.length),
              // ── 탭 필터 ───────────────────────────────────────
              _buildTabFilter(),
              const SizedBox(height: 4),
              // ── 배지 목록 ─────────────────────────────────────
              if (filtered.isEmpty)
                _buildEmptyState()
              else
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      for (final entry in grouped.entries) ...[
                        _buildGroupHeader(entry.key),
                        for (final badge in entry.value)
                          _buildBadgeItem(badge),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── 데이터 가공 ──────────────────────────────────────────────────

  List<BadgeModel> _filter(List<BadgeModel> earned) {
    switch (_selectedTab) {
      case 1: return earned.where((b) => b.type == BadgeType.experience).toList();
      case 2: return earned.where((b) => b.type == BadgeType.attendance).toList();
      case 3: return earned.where((b) => b.type == BadgeType.specialty).toList();
      default: return earned;
    }
  }

  /// 표시 그룹 구성 (카테고리별 섹션)
  Map<String, List<BadgeModel>> _group(List<BadgeModel> badges) {
    final result = <String, List<BadgeModel>>{};
    for (final badge in badges) {
      final key = _groupLabel(badge.type);
      result.putIfAbsent(key, () => []).add(badge);
    }
    return result;
  }

  String _groupLabel(BadgeType type) {
    switch (type) {
      case BadgeType.experience:  return '근무 성취';
      case BadgeType.attendance:  return '출근 기록';
      case BadgeType.specialty:   return '특별 경험';
      case BadgeType.trustScore:  return '기타';
    }
  }

  // ── 배지 시각화 helpers ──────────────────────────────────────────

  /// 조건 기반 표시 이름 생성 — badge.name(관리자 입력)을 사용하지 않는다.
  /// "베테랑/마스터" 같은 등급형 명칭 대신 달성 내용을 즉시 이해할 수 있는
  /// 구체적인 이름을 보여준다. 예: "100회 근무", "5회 연속 출근"
  static String _badgeTitle(BadgeModel badge) {
    switch (badge.conditionType) {
      case BadgeConditionType.workDays:           return '${badge.conditionValue}회 근무';
      case BadgeConditionType.consecutive:        return '${badge.conditionValue}회 연속 출근';
      case BadgeConditionType.monthlyPerfect:     return '월간 완근';
      case BadgeConditionType.sameBusinessRehire: return '재고용 ${badge.conditionValue}회';
      case BadgeConditionType.uniqueBusinesses:   return '${badge.conditionValue}곳 경험';
      case BadgeConditionType.nightShiftCount:    return '야간 ${badge.conditionValue}회';
      case BadgeConditionType.earlyBirdCount:     return '새벽 ${badge.conditionValue}회';
      case BadgeConditionType.weekendCount:       return '주말 ${badge.conditionValue}회';
      case BadgeConditionType.minScore:           return '신뢰도 ${badge.conditionValue}점';
    }
  }

  static IconData _conditionIcon(BadgeConditionType type) {
    switch (type) {
      case BadgeConditionType.workDays:           return Icons.check_circle_outline;
      case BadgeConditionType.consecutive:        return Icons.trending_up;
      case BadgeConditionType.monthlyPerfect:     return Icons.calendar_today_outlined;
      case BadgeConditionType.sameBusinessRehire: return Icons.storefront_outlined;
      case BadgeConditionType.uniqueBusinesses:   return Icons.explore_outlined;
      case BadgeConditionType.nightShiftCount:    return Icons.nightlight_outlined;
      case BadgeConditionType.earlyBirdCount:     return Icons.wb_sunny_outlined;
      case BadgeConditionType.weekendCount:       return Icons.event_note_outlined;
      case BadgeConditionType.minScore:           return Icons.shield_outlined;
    }
  }

  static Color _categoryColor(BadgeType type) {
    switch (type) {
      case BadgeType.attendance:  return AppColors.successDark;
      case BadgeType.experience:  return AppColors.infoDark;
      case BadgeType.specialty:   return AppColors.amberDark;
      case BadgeType.trustScore:  return AppColors.grey500;
    }
  }

  static String _describe(BadgeModel badge) {
    switch (badge.conditionType) {
      case BadgeConditionType.workDays:
        return '${badge.conditionValue}번의 근무를 완료했어요';
      case BadgeConditionType.consecutive:
        return '${badge.conditionValue}회 연속 정상 출근했어요';
      case BadgeConditionType.monthlyPerfect:
        return '한 달 동안 100% 출근을 달성했어요';
      case BadgeConditionType.sameBusinessRehire:
        return '같은 사업장에서 ${badge.conditionValue}회 재고용됐어요';
      case BadgeConditionType.uniqueBusinesses:
        return '${badge.conditionValue}개 이상의 다른 사업장을 경험했어요';
      case BadgeConditionType.nightShiftCount:
        return '야간(22시 이후) 근무 ${badge.conditionValue}회를 완료했어요';
      case BadgeConditionType.earlyBirdCount:
        return '새벽(6시 이전) 출근 ${badge.conditionValue}회를 완료했어요';
      case BadgeConditionType.weekendCount:
        return '주말·공휴일 근무 ${badge.conditionValue}회를 완료했어요';
      case BadgeConditionType.minScore:
        return '신뢰도 ${badge.conditionValue}점을 달성했어요';
    }
  }

  // ── 위젯 builders ────────────────────────────────────────────────

  Widget _buildHeader(int earnedCount) {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Text(
        earnedCount == 0
            ? '아직 획득한 활동 배지가 없어요'
            : '$earnedCount개의 활동 배지를 획득했어요',
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _buildTabFilter() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: List.generate(_tabs.length, (i) => _buildTabChip(i)),
      ),
    );
  }

  Widget _buildTabChip(int index) {
    final selected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.infoDark : AppColors.background,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _tabs[index],
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textHint,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildBadgeItem(BadgeModel badge) {
    final color = _categoryColor(badge.type);
    final icon = _conditionIcon(badge.conditionType);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          // 아이콘
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          // 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _badgeTitle(badge),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _describe(badge),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final categoryName = _selectedTab == 0 ? '활동' : _tabs[_selectedTab];
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events_outlined,
                size: 40, color: AppColors.grey300),
            const SizedBox(height: 12),
            Text(
              '아직 획득한 $categoryName 배지가 없어요',
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
