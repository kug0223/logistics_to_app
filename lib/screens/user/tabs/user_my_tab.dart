// lib/screens/user/tabs/user_my_tab.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/core/user_model.dart';
import '../../../models/settings/trust_settings_model.dart';
import '../../../providers/badge_provider.dart';
import '../../../providers/user_provider.dart';
import '../../../theme/app_colors.dart';
import '../../common/document_management_screen.dart';
import '../../common/profile_edit_screen.dart';
import '../signature_screen.dart';
import '../my_activity_screen.dart';
import '../user_contracts_screen.dart';
import '../user_settings_screen.dart';

/// MY 탭 — 사용자 본인 정보·근무 활동 허브
///
/// ## 구조
/// 1. 프로필 헤더 (이름, 가입일)
/// 2. 근무 기록 (완료 근무·총 시간·출근율)
/// 3. 나의 활동 (획득 배지 최대 3개 + 전체보기 → MyActivityScreen)
/// 4. 근무 관리 (계약서, 내 서류 관리, 내 서명 → SignatureScreen)
/// 5. 내 정보 (프로필 관리)
/// 6. 설정 (→ UserSettingsScreen)
///
/// ## 신뢰점수 제거 결정
/// 신뢰점수 UI는 사용자에게 노출하지 않는다.
/// 실제 근무 데이터(완료 회수·출근율)로 대체.
///
/// ## 배지 설계 방향
/// 신뢰도 등급(👑 마스터) 게임화 × → 근무 이력 성취 기록 ○
/// BadgeType.trustScore 배지는 이 화면에서 완전히 숨긴다.
class UserMyTab extends StatelessWidget {
  const UserMyTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'MY',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderLight),
        ),
      ),
      body: Selector<UserProvider, UserModel?>(
        selector: (_, p) => p.currentUser,
        builder: (context, user, _) {
          if (user == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              _ProfileHeader(user: user),
              _CareerSummary(user: user),
              _ActivitySection(userBadgeIds: user.badges),
              const SizedBox(height: 8),
              _MenuSection(
                title: '근무 관리',
                items: [
                  _MenuItem(
                    icon: Icons.folder_copy_outlined,
                    label: '계약서',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const UserContractsScreen()),
                    ),
                  ),
                  _MenuItem(
                    icon: Icons.description_outlined,
                    label: '내 서류 관리',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DocumentManagementScreen()),
                    ),
                  ),
                  _MenuItem(
                    icon: Icons.draw_outlined,
                    label: '내 서명',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SignatureScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _MenuSection(
                title: '내 정보',
                items: [
                  _MenuItem(
                    icon: Icons.person_outline,
                    label: '프로필 관리',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProfileEditScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ── 설정 섹션 ─────────────────────────────────────────
              _MenuSection(
                title: '설정',
                items: [
                  _MenuItem(
                    icon: Icons.settings_outlined,
                    label: '설정',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const UserSettingsScreen()),
                    ),
                  ),
                ],
              ),
              // ── 관리자 전환 (하위관리자 전용) ──────────────────────
              if (user.isSubAdmin) ...[
                const SizedBox(height: 8),
                _MenuSection(
                  title: '관리자',
                  items: [
                    _MenuItem(
                      icon: Icons.admin_panel_settings_outlined,
                      label: '관리자 모드로 전환',
                      onTap: () async {
                        final up = context.read<UserProvider>();
                        final bizIds = user.subAdminBusinessIds;
                        if (bizIds.isEmpty) return;
                        String? selected;
                        if (bizIds.length == 1) {
                          selected = bizIds.first;
                        } else {
                          selected = await showDialog<String>(
                            context: context,
                            builder: (ctx) => SimpleDialog(
                              title: const Text('관리자 사업장 선택'),
                              children: [
                                for (final id in bizIds)
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(ctx, id),
                                    child: Text(up.subAdminBusinessNames[id] ?? id),
                                  ),
                              ],
                            ),
                          );
                        }
                        if (selected == null || !context.mounted) return;
                        // switchToAdminMode → notifyListeners() → AuthWrapper 반응형 라우팅 → BusinessAdminShell
                        await up.switchToAdminMode(selected);
                      },
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 48),
            ],
          );
        },
      ),
    );
  }
}

// ── 프로필 헤더 ───────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final UserModel user;
  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    final initial = user.name.isNotEmpty ? user.name[0] : '?';
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        children: [
          // 이니셜 아바타
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.infoDark, AppColors.info],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                if (user.createdAt != null)
                  Text(
                    '${user.createdAt!.year}.${user.createdAt!.month.toString().padLeft(2, '0')} 가입',
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
}

// ── 근무 기록 요약 ────────────────────────────────────────────────

class _CareerSummary extends StatelessWidget {
  final UserModel user;
  const _CareerSummary({required this.user});

  @override
  Widget build(BuildContext context) {
    final attendanceRate = _calcRate(user);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: AppColors.borderLight),
          const SizedBox(height: 16),
          const Text(
            '근무 기록',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // 완료 근무
              _StatCell(
                value: '${user.totalWorkDays}회',
                label: '완료 근무',
              ),
              _statDivider(),
              // 총 시간 — totalWorkDays > 0 일 때만 표시 (0h 오표시 방지)
              if (user.totalWorkDays > 0 && user.totalWorkHours > 0) ...[
                _StatCell(
                  value: '${user.totalWorkHours.round()}h',
                  label: '총 시간',
                ),
                _statDivider(),
              ],
              // 출근율
              _StatCell(
                value: '$attendanceRate%',
                label: '출근율',
                valueColor: attendanceRate >= 90
                    ? AppColors.successDark
                    : attendanceRate >= 70
                        ? AppColors.warningDark
                        : AppColors.error,
              ),
            ],
          ),
          // 선호 업무 칩
          if ((user.preferredWorkTypes ?? []).isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: (user.preferredWorkTypes ?? [])
                  .map((t) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.infoBg,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                              color:
                                  AppColors.infoDark.withValues(alpha: 0.25)),
                        ),
                        child: Text(t,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.infoDark,
                              fontWeight: FontWeight.w600,
                            )),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: AppColors.borderLight,
      );

  int _calcRate(UserModel user) {
    final total = user.totalWorkDays + user.noShowCount;
    if (total == 0) return 100;
    return ((user.totalWorkDays / total) * 100).round();
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;

  const _StatCell({
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: valueColor ?? AppColors.textPrimary,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── 나의 활동 (배지 섹션) ─────────────────────────────────────────

/// 획득 배지를 최대 3개 미리보기로 보여주는 MY 탭 섹션.
///
/// 배지 없으면 섹션 자체를 숨긴다 (early return SizedBox).
/// "전체보기"는 [MyActivityScreen] 으로 push 이동.
///
/// ## 배지 시각 언어
/// - 근무(experience): 파란색(infoDark) — 근무 횟수·사업장 다양성
/// - 출근(attendance): 초록색(successDark) — 연속 출근·야간·주말
/// - 특별(specialty): 황금색(amberDark) — 특별 성취
/// - 신뢰도(trustScore): 표시 안 함
class _ActivitySection extends StatelessWidget {
  final List<String> userBadgeIds;
  const _ActivitySection({required this.userBadgeIds});

  @override
  Widget build(BuildContext context) {
    if (userBadgeIds.isEmpty) return const SizedBox.shrink();

    return Consumer<BadgeProvider>(
      builder: (context, badgeProvider, _) {
        // trustScore 계열 배지 완전 제외 — 신뢰도 점수 시스템 UI 제거 결정
        final earnedBadges = badgeProvider.badges
            .where((b) =>
                userBadgeIds.contains(b.id) &&
                b.type != BadgeType.trustScore)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));

        if (earnedBadges.isEmpty) return const SizedBox.shrink();

        final preview = earnedBadges.take(3).toList();
        final remaining = earnedBadges.length - preview.length;

        return Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 1, color: AppColors.borderLight),
              const SizedBox(height: 16),
              // ── 섹션 헤더 ──────────────────────────────────────
              Row(
                children: [
                  const Text(
                    '나의 활동',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MyActivityScreen(
                          userBadgeIds: userBadgeIds,
                        ),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '전체보기',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.infoDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(width: 2),
                        Icon(Icons.chevron_right,
                            size: 14, color: AppColors.infoDark),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // ── 배지 칩 행 ─────────────────────────────────────
              Row(
                children: [
                  for (final badge in preview) ...[
                    _AchievementBadgeChip(badge: badge),
                    const SizedBox(width: 8),
                  ],
                  if (remaining > 0) _MoreBadgeIndicator(count: remaining),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── 배지 칩 ───────────────────────────────────────────────────────

/// 근무 성취 배지 — 소형 카드 (76×auto)
///
/// 그라데이션·글로우·이모지 없음. 플랫 컬러 + Material Icons.
/// 세로 구성: 컬러 원형 아이콘 + 배지명 텍스트.
class _AchievementBadgeChip extends StatelessWidget {
  final BadgeModel badge;
  // ignore: super.key는 private 클래스라 호출 측에서 전달하지 않음
  const _AchievementBadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    final color = _badgeColor(badge.type);
    final icon = _conditionIcon(badge.conditionType);

    return Container(
      width: 76,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 아이콘 원
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 6),
          // 배지명 — MY Preview용 짧은 이름, 최대 1줄
          Text(
            _badgeShortTitle(badge),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
              height: 1.3,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// MY Preview용 짧은 표시명 — 1줄 원칙
  ///
  /// 달성 횟수가 핵심 식별 정보인 workDays(100회 근무 / 200회 근무)만
  /// 숫자를 포함한다. 그 외는 카테고리명만 표시해 카드 폭 안에서 깨지지 않도록 한다.
  /// 상세 달성 조건은 나의 활동 전체보기(MyActivityScreen)에서 제공한다.
  static String _badgeShortTitle(BadgeModel badge) {
    switch (badge.conditionType) {
      case BadgeConditionType.workDays:           return '${badge.conditionValue}회 근무';
      case BadgeConditionType.consecutive:        return '연속 출근';
      case BadgeConditionType.monthlyPerfect:     return '월간 완근';
      case BadgeConditionType.sameBusinessRehire: return '재고용';
      case BadgeConditionType.uniqueBusinesses:   return '${badge.conditionValue}곳 경험';
      case BadgeConditionType.nightShiftCount:    return '야간 근무';
      case BadgeConditionType.earlyBirdCount:     return '새벽 출근';
      case BadgeConditionType.weekendCount:       return '주말 근무';
      case BadgeConditionType.minScore:           return '신뢰도';
    }
  }

  static Color _badgeColor(BadgeType type) {
    switch (type) {
      case BadgeType.attendance:  return AppColors.successDark;
      case BadgeType.experience:  return AppColors.infoDark;
      case BadgeType.specialty:   return AppColors.amberDark;
      case BadgeType.trustScore:  return AppColors.grey500;
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
}

/// 초과 배지 개수 표시기 — "+N" 회색 원형
class _MoreBadgeIndicator extends StatelessWidget {
  final int count;
  const _MoreBadgeIndicator({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.grey100,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Center(
        child: Text(
          '+$count',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── 메뉴 섹션 ─────────────────────────────────────────────────────

class _MenuSection extends StatelessWidget {
  final String title;
  final List<_MenuItem> items;

  const _MenuSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textHint,
                letterSpacing: 0.4,
              ),
            ),
          ),
          ...items,
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

// ── 메뉴 아이템 ───────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.textSecondary, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.grey300, size: 18),
        ]),
      ),
    );
  }
}
