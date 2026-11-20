// lib/screens/user/my_activity_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/settings/trust_settings_model.dart';
import '../../providers/badge_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/text_layout.dart';
import '../../widgets/common/app_empty_state.dart';

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
                        _buildBadgeGroup(entry.value),
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
      case BadgeType.specialty:   return AppColors.warningDark; // [DU250] amberDark 는 자기 옅은 원 위 1.9 — 4.58
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
      // [DU250 v2] 큰 글자에서 낱말 단위로만 줄을 바꾼다(B320 '획/득했어요' 음절 끊김). 읽기 도구에는 원문.
      child: Text(
        TextLayout.keepWords(earnedCount == 0
            ? '아직 획득한 활동 배지가 없어요'
            : '$earnedCount개의 활동 배지를 획득했어요'),
        semanticsLabel: earnedCount == 0
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
      width: double.infinity, // [DU250 v2] Wrap 은 내용 폭만 쓴다 — 흰 띠는 화면 폭 전체
      color: Colors.white,
      // [DU250] 칩 터치 높이 48 만큼 아래 여백을 덜어낸다(12 → 4).
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      // [DU250] 큰 글자에서 칩 줄이 49px 넘쳤다(B320) — 넘치면 다음 줄로 내린다.
      child: Wrap(
        children: List.generate(_tabs.length, (i) => _buildTabChip(i)),
      ),
    );
  }

  Widget _buildTabChip(int index) {
    final selected = _selectedTab == index;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      // [DU250] 선택은 대표색(UI-1). 칩 모양은 그대로 두고 터치 높이만 48 로 넓힌다(이전 약 30).
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selectedTab = index),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppColors.brand : AppColors.background,
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
        ),
      ),
    );
  }

  Widget _buildGroupHeader(String label) {
    return Padding(
      // [DU250] 섹션 제목 — S010·S082·S040 과 같은 16 bold 본문색(이전 12 textHint, 바탕 위 1.75).
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  /// [DU250] 분류 하나 = 묶음 카드 하나(S010·S082 와 같은 흰 면·반경 16·grey200). 이전에는 배지마다 따로 카드였다.
  Widget _buildBadgeGroup(List<BadgeModel> badges) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.grey200),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < badges.length; i++) ...[
              _buildBadgeItem(badges[i]),
              if (i < badges.length - 1)
                const Divider(
                    height: 1, thickness: 1, color: AppColors.grey100, indent: 72),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeItem(BadgeModel badge) {
    // 아이콘의 분류 색(출근·근무·특별)은 MY 탭 배지 줄과 같은 성취 분류 표시라 유지한다.
    final color = _categoryColor(badge.type);
    final icon = _conditionIcon(badge.conditionType);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                // [DU250] 큰 글자에서 낱말 단위로만 줄을 바꾼다. 읽기 도구에는 원문.
                Text(
                  TextLayout.keepWords(_badgeTitle(badge)),
                  semanticsLabel: _badgeTitle(badge),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  TextLayout.keepWords(_describe(badge)),
                  semanticsLabel: _describe(badge),
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
    // [DU250] 공용 빈 상태(AppEmptyState)로 — 다른 화면의 빈 상태와 같은 크기·읽기색(DU248).
    return Expanded(
      child: AppEmptyState(
        icon: Icons.emoji_events_outlined,
        title: '아직 획득한 $categoryName 배지가 없어요',
      ),
    );
  }
}
