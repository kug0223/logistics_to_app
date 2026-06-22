import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';
import 'all_businesses_screen.dart';
import 'all_users_screen.dart';
import 'foreign_worker_approval_screen.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../common/settings_screen.dart';
import 'system_settings_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/toast_helper.dart';

/// 최고관리자(SUPER_ADMIN) 홈 화면
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  late final Future<_SuperAdminStats> _statsFuture = _loadStats();

  Future<_SuperAdminStats> _loadStats() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').count().get(),
        FirebaseFirestore.instance.collection('businesses').count().get(),
        FirebaseFirestore.instance
            .collection('users')
            .where('accountStatus', isEqualTo: 'pending')
            .count()
            .get(),
      ]);
      return _SuperAdminStats(
        totalUsers: results[0].count ?? 0,
        totalBusinesses: results[1].count ?? 0,
        pendingApprovals: results[2].count ?? 0,
      );
    } catch (_) {
      return const _SuperAdminStats(
          totalUsers: 0, totalBusinesses: 0, pendingApprovals: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        final user = userProvider.currentUser;
        final theme = Theme.of(context);
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [theme.primaryColor, theme.colorScheme.secondary],
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 상단 헤더 ──────────────────────────────────
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 24),
                      vertical: ResponsiveHelper.spacing(
                          context, isLandscape ? 8 : 20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Text(
                                      'ALfit',
                                      style: ResponsiveHelper.titleStyle(context)
                                          .copyWith(
                                        color: Colors.white,
                                        fontSize:
                                            ResponsiveHelper.titleStyle(context)
                                                    .fontSize! *
                                                1.3,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    Positioned(
                                      right: -ResponsiveHelper.spacing(context, 3),
                                      top: ResponsiveHelper.spacing(context, 5),
                                      child: Container(
                                        width: ResponsiveHelper.spacing(context, 4),
                                        height: ResponsiveHelper.spacing(context, 4),
                                        decoration: BoxDecoration(
                                          color:
                                              Colors.white.withValues(alpha: 0.8),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                    width:
                                        ResponsiveHelper.spacing(context, 12)),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal:
                                        ResponsiveHelper.spacing(context, 10),
                                    vertical:
                                        ResponsiveHelper.spacing(context, 5),
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.admin_panel_settings,
                                        color: Colors.white,
                                        size: ResponsiveHelper.iconSize(
                                            context, 14),
                                      ),
                                      SizedBox(
                                          width: ResponsiveHelper.spacing(
                                              context, 4)),
                                      Text(
                                        '최고',
                                        style: ResponsiveHelper.tinyStyle(
                                          context,
                                          color: Colors.white,
                                        ).copyWith(fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Material(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                onTap: () async {
                                  final confirmed =
                                      await DialogHelper.showLogoutConfirm(
                                          context);
                                  if (confirmed && context.mounted) {
                                    context.read<ThemeProvider>().reset();
                                    await userProvider.signOut();
                                  }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: EdgeInsets.all(
                                      ResponsiveHelper.spacing(context, 8)),
                                  child: Icon(
                                    Icons.logout,
                                    color: Colors.white,
                                    size: ResponsiveHelper.iconSize(context, 24),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!isLandscape) ...[
                          SizedBox(
                              height: ResponsiveHelper.spacing(context, 24)),
                          Text(
                            '안녕하세요,',
                            style: ResponsiveHelper.bodyStyle(
                              context,
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                          ),
                          SizedBox(
                              height: ResponsiveHelper.spacing(context, 8)),
                          Text(
                            '${user?.name ?? '관리자'}님',
                            style: ResponsiveHelper.titleStyle(context).copyWith(
                              color: Colors.white,
                              fontSize:
                                  ResponsiveHelper.titleStyle(context).fontSize! *
                                      1.5,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── 메뉴 영역 ──────────────────────────────────
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.grey50,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(
                            ResponsiveHelper.spacing(context, 20)),
                        child: Column(
                          children: [
                            // ── 통계 요약 카드 ──────────────────
                            FutureBuilder<_SuperAdminStats>(
                              future: _statsFuture,
                              builder: (context, snap) {
                                final stats = snap.data;
                                return Row(
                                  children: [
                                    _buildStatCard(
                                      context,
                                      label: '전체 회원',
                                      value: stats != null
                                          ? '${stats.totalUsers}명'
                                          : '-',
                                      icon: Icons.people_outline,
                                      color: theme.primaryColor,
                                    ),
                                    SizedBox(
                                        width: ResponsiveHelper.spacing(
                                            context, 8)),
                                    _buildStatCard(
                                      context,
                                      label: '전체 사업장',
                                      value: stats != null
                                          ? '${stats.totalBusinesses}개'
                                          : '-',
                                      icon: Icons.business_outlined,
                                      color: AppColors.purple,
                                    ),
                                    SizedBox(
                                        width: ResponsiveHelper.spacing(
                                            context, 8)),
                                    _buildStatCard(
                                      context,
                                      label: '승인 대기',
                                      value: stats != null
                                          ? '${stats.pendingApprovals}명'
                                          : '-',
                                      icon: Icons.pending_outlined,
                                      color: (stats?.pendingApprovals ?? 0) > 0
                                          ? AppColors.warning
                                          : AppColors.grey400,
                                    ),
                                  ],
                                );
                              },
                            ),
                            SizedBox(
                                height: ResponsiveHelper.spacing(context, 16)),

                            // ── 메뉴 그리드 ────────────────────
                            Expanded(
                              child: GridView.count(
                                crossAxisCount: 2,
                                crossAxisSpacing:
                                    ResponsiveHelper.spacing(context, 16),
                                mainAxisSpacing:
                                    ResponsiveHelper.spacing(context, 16),
                                children: [
                                  _buildMenuCard(
                                    context,
                                    icon: Icons.business_center,
                                    title: '모든 사업장',
                                    subtitle: '전체 사업장 관리',
                                    color: theme.primaryColor,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const AllBusinessesScreen()),
                                    ),
                                  ),
                                  _buildMenuCard(
                                    context,
                                    icon: Icons.dashboard_outlined,
                                    title: '공고 모니터링',
                                    subtitle: '전체 공고 현황',
                                    color: AppColors.grey400,
                                    isDisabled: true,
                                    onTap: () => ToastHelper.showInfo(
                                        '공고 모니터링 기능은 준비 중입니다'),
                                  ),
                                  _buildMenuCard(
                                    context,
                                    icon: Icons.people_outline,
                                    title: '사용자 관리',
                                    subtitle: '회원 관리',
                                    color: theme.primaryColor,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const AllUsersScreen()),
                                    ),
                                  ),
                                  _buildMenuCard(
                                    context,
                                    icon: Icons.analytics_outlined,
                                    title: '통계',
                                    subtitle: '전체 통계 분석',
                                    color: AppColors.grey400,
                                    isDisabled: true,
                                    onTap: () => ToastHelper.showInfo(
                                        '통계 기능은 준비 중입니다'),
                                  ),
                                  _buildMenuCard(
                                    context,
                                    icon: Icons.admin_panel_settings,
                                    title: '시스템 설정',
                                    subtitle: '규칙/태그/배지',
                                    color: theme.primaryColor,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const SystemSettingsScreen()),
                                    ),
                                  ),
                                  _buildMenuCard(
                                    context,
                                    icon: Icons.how_to_reg_outlined,
                                    title: '외국인 승인',
                                    subtitle: '가입 승인/거절',
                                    color: AppColors.warning,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const ForeignWorkerApprovalScreen()),
                                    ),
                                  ),
                                  _buildMenuCard(
                                    context,
                                    icon: Icons.settings_outlined,
                                    title: '설정',
                                    subtitle: '개인 설정',
                                    color: AppColors.grey600,
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              const SettingsScreen()),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 12),
          horizontal: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: ResponsiveHelper.iconSize(context, 22), color: color),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              value,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isDisabled = false,
  }) {
    return Card(
      elevation: isDisabled ? 0 : 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: isDisabled ? AppColors.grey100 : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: ResponsiveHelper.iconSize(context, 32),
                    color: color,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                Text(
                  title,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDisabled ? AppColors.grey400 : null,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  isDisabled ? '준비 중' : subtitle,
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: isDisabled ? AppColors.grey300 : AppColors.grey600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuperAdminStats {
  final int totalUsers;
  final int totalBusinesses;
  final int pendingApprovals;

  const _SuperAdminStats({
    required this.totalUsers,
    required this.totalBusinesses,
    required this.pendingApprovals,
  });
}
