import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/fcm_service.dart';
import 'all_businesses_screen.dart';
import 'all_users_screen.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../common/settings_screen.dart';
import '../common/notification_screen.dart';
import 'system_settings_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/notification_badge.dart';

/// 최고관리자(SUPER_ADMIN) 홈 화면
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  _SuperAdminStats? _stats;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStats();
    // [Phase 9D] cold-start pending payload 소비
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FCMService().consumePendingColdStartPayload();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱이 백그라운드에서 복귀할 때 통계 갱신
    if (state == AppLifecycleState.resumed) {
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').count().get(),
        FirebaseFirestore.instance.collection('businesses').count().get(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = _SuperAdminStats(
          totalUsers: results[0].count ?? 0,
          totalBusinesses: results[1].count ?? 0,
        );
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 슈퍼관리자 통계 로드 실패: $e');
      if (!mounted) return;
      setState(() {
        _stats = const _SuperAdminStats(
            totalUsers: 0, totalBusinesses: 0);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Selector<UserProvider, String?>(
      // [PERF] 이름 1개만 구독 — 다른 UserProvider 변경 시 rebuild 방지
      selector: (_, p) => p.currentUser?.name,
      builder: (context, userName, _) {
        final theme = Theme.of(context);
        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;

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
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 상단 헤더 ──────────────────────────────────
                  _buildHeader(context, theme, isLandscape, userName),

                  // ── 스크롤 가능 콘텐츠 영역 ────────────────────
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.grey50,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      child: RefreshIndicator(
                        onRefresh: _loadStats,
                        child: _buildBody(context, theme, isLandscape),
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

  // ────────────────────────────────────────────────────────────
  //  헤더
  // ────────────────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    bool isLandscape,
    String? userName,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 24),
        vertical: ResponsiveHelper.spacing(context, isLandscape ? 8 : 20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1행: 로고 + 뱃지 + 알림·로그아웃
          Row(
            children: [
              // 로고 + ALfit 텍스트
              ClipOval(
                child: Image.asset(
                  'assets/icons/app_icon.png',
                  width: ResponsiveHelper.spacing(context, 26),
                  height: ResponsiveHelper.spacing(context, 26),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                'ALfit',
                style: ResponsiveHelper.titleStyle(context).copyWith(
                  color: Colors.white,
                  fontSize:
                      ResponsiveHelper.titleStyle(context).fontSize! * 1.3,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              // 최고관리자 뱃지
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 5),
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
                      size: ResponsiveHelper.iconSize(context, 14),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
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

              const Spacer(),

              // 알림 벨
              NotificationBadge(
                child: Material(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NotificationScreen()),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding:
                          EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                      child: Icon(
                        Icons.notifications_outlined,
                        color: Colors.white,
                        size: ResponsiveHelper.iconSize(context, 22),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),

              // 로그아웃
              Material(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () async {
                    final confirmed =
                        await DialogHelper.showLogoutConfirm(context);
                    if (confirmed && context.mounted) {
                      // signOut 먼저: 실패 시 ThemeProvider.reset() 호출 방지
                      await context.read<UserProvider>().signOut();
                      if (context.mounted) {
                        context.read<ThemeProvider>().reset();
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding:
                        EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                    child: Icon(
                      Icons.logout,
                      color: Colors.white,
                      size: ResponsiveHelper.iconSize(context, 22),
                    ),
                  ),
                ),
              ),
            ],
          ),

          // 2행: 인사말 (가로 모드에서는 생략)
          if (!isLandscape) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
            Text(
              '안녕하세요,',
              style: ResponsiveHelper.bodyStyle(
                context,
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              '${userName ?? '관리자'}님',
              style: ResponsiveHelper.titleStyle(context).copyWith(
                color: Colors.white,
                fontSize:
                    ResponsiveHelper.titleStyle(context).fontSize! * 1.5,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  메인 스크롤 바디
  // ────────────────────────────────────────────────────────────

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    bool isLandscape,
  ) {
    return ListView(
      // listPadding: 하단 홈 인디케이터 높이를 자동 추가
      padding: ResponsiveHelper.listPadding(context,
          extra: ResponsiveHelper.spacing(context, 8)),
      children: [
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        // ── 통계 요약 ──────────────────────────────────────
        _buildStatsRow(context, theme),
        SizedBox(height: ResponsiveHelper.spacing(context, 24)),

        // ── 관리 섹션 ──────────────────────────────────────
        _buildSectionLabel(context, '관리'),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        _buildMenuTile(
          context,
          icon: Icons.business_center_outlined,
          color: theme.primaryColor,
          title: '모든 사업장',
          subtitle: '전체 사업장 현황 및 관리',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AllBusinessesScreen()),
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        _buildMenuTile(
          context,
          icon: Icons.people_outline,
          color: theme.primaryColor,
          title: '사용자 관리',
          subtitle: '회원 목록 조회 및 정보 관리',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AllUsersScreen()),
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),

        // ── 시스템 섹션 ────────────────────────────────────
        _buildSectionLabel(context, '시스템'),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        _buildMenuTile(
          context,
          icon: Icons.admin_panel_settings_outlined,
          color: AppColors.purple,
          title: '시스템 설정',
          subtitle: '신뢰도 규칙·배지·임금·공고 설정 관리',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SystemSettingsScreen()),
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),

        // ── 개인 섹션 ──────────────────────────────────────
        _buildSectionLabel(context, '개인'),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        _buildMenuTile(
          context,
          icon: Icons.settings_outlined,
          color: AppColors.grey600,
          title: '설정',
          subtitle: '개인 설정 및 테마',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),

        // ── 준비 중 섹션 ──────────────────────────────────
        _buildSectionLabel(context, '준비 중'),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        _buildMenuTile(
          context,
          icon: Icons.dashboard_outlined,
          color: AppColors.grey400,
          title: '공고 모니터링',
          subtitle: '전체 공고 현황 분석',
          isDisabled: true,
          onTap: () => ToastHelper.showInfo('공고 모니터링 기능은 준비 중입니다'),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        _buildMenuTile(
          context,
          icon: Icons.analytics_outlined,
          color: AppColors.grey400,
          title: '전체 통계',
          subtitle: '플랫폼 전체 통계 분석',
          isDisabled: true,
          onTap: () => ToastHelper.showInfo('통계 기능은 준비 중입니다'),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────────────────
  //  통계 행
  // ────────────────────────────────────────────────────────────

  Widget _buildStatsRow(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        _buildStatCard(
          context,
          label: '전체 회원',
          value: _isLoading ? '-' : '${_stats?.totalUsers ?? 0}명',
          icon: Icons.people_outline,
          color: theme.primaryColor,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        _buildStatCard(
          context,
          label: '전체 사업장',
          value: _isLoading ? '-' : '${_stats?.totalBusinesses ?? 0}개',
          icon: Icons.business_outlined,
          color: AppColors.purple,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    bool highlight = false,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 12),
          horizontal: ResponsiveHelper.spacing(context, 6),
        ),
        decoration: BoxDecoration(
          color: highlight ? color.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: highlight
              ? Border.all(color: color.withValues(alpha: 0.25))
              : null,
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
            Icon(icon,
                size: ResponsiveHelper.iconSize(context, 22), color: color),
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
              style:
                  ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  섹션 레이블
  // ────────────────────────────────────────────────────────────

  Widget _buildSectionLabel(BuildContext context, String title) {
    return Padding(
      padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 4)),
      child: Text(
        title,
        style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)
            .copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  //  메뉴 타일 (리스트 카드)
  // ────────────────────────────────────────────────────────────

  Widget _buildMenuTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
    bool isDisabled = false,
  }) {
    return Material(
      color: isDisabled ? AppColors.grey100 : Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: isDisabled ? 0 : 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.07),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 14),
          ),
          child: Row(
            children: [
              // 아이콘 원형
              Container(
                width: ResponsiveHelper.spacing(context, 44),
                height: ResponsiveHelper.spacing(context, 44),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDisabled ? 0.06 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: ResponsiveHelper.iconSize(context, 22),
                  color: isDisabled ? AppColors.grey400 : color,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 14)),

              // 텍스트
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDisabled
                            ? AppColors.grey400
                            : AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                    Text(
                      isDisabled ? '준비 중' : subtitle,
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // 대기 건수 뱃지 (외국인 승인 등)
              if (badge != null) ...[
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 3),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warning,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badge,
                    style: ResponsiveHelper.tinyStyle(
                      context,
                      color: Colors.white,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              ],

              // 화살표 (비활성 항목은 숨김)
              if (!isDisabled)
                Icon(
                  Icons.chevron_right,
                  color: AppColors.grey300,
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
//  데이터 모델
// ──────────────────────────────────────────────────────────────

class _SuperAdminStats {
  final int totalUsers;
  final int totalBusinesses;

  const _SuperAdminStats({
    required this.totalUsers,
    required this.totalBusinesses,
  });
}
