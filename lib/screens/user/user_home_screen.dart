import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/tour_helper.dart';
import '../common/tour_screen.dart';
import 'all_to_list_screen.dart';
import 'my_schedule_screen.dart';
import 'attendance_check_screen.dart';
import 'my_applications_screen.dart';
import 'my_reviews_screen.dart';
import 'user_contracts_screen.dart';
import '../common/settings_screen.dart';
import '../common/notification_screen.dart';
import '../../widgets/common/notification_badge.dart';
import '../../models/core/user_model.dart';
import '../../theme/app_colors.dart';

/// 일반 사용자 홈 화면
class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!await TourHelper.isCompleted(TourHelper.userHome)) {
        if (mounted) _showTourDialog();
      }
    });
  }

  Future<void> _showTourDialog() async {
    await pushTourScreen(context, role: 'USER');
    await TourHelper.markCompleted(TourHelper.userHome);
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final theme = Theme.of(context);

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
              // 상단 헤더
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 24),
                  vertical: ResponsiveHelper.spacing(context, 16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 맨 위 바 (ALfit 로고 + 로그아웃)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // ALfit 로고 + 점 (오른쪽 위)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Text(
                              'ALfit',
                              style: ResponsiveHelper.titleStyle(context).copyWith(
                                color: Colors.white,
                                fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 1.3,
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
                                  color: Colors.white.withValues(alpha: 0.8),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // 🔔 알림 + 로그아웃 버튼
                        Row(
                          children: [
                            NotificationBadge(
                              child: Material(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                                child: Semantics(
                                  label: '알림',
                                  button: true,
                                  child: InkWell(
                                    onTap: () => Navigator.push(context,
                                        MaterialPageRoute(builder: (_) => const NotificationScreen())),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                                      child: Icon(Icons.notifications_outlined,
                                          color: Colors.white,
                                          size: ResponsiveHelper.iconSize(context, 24)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            Material(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                              child: Semantics(
                                label: '로그아웃',
                                button: true,
                                child: InkWell(
                                  onTap: () async {
                                    final confirmed = await DialogHelper.showLogoutConfirm(context);
                                    if (confirmed && context.mounted) {
                                      context.read<ThemeProvider>().reset();
                                      await userProvider.signOut();
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                                    child: Icon(Icons.logout,
                                        color: Colors.white,
                                        size: ResponsiveHelper.iconSize(context, 24)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                    Text(
                      '안녕하세요,',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: Colors.white.withValues(alpha: 0.95)),
                    ),

                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                    // 사용자 이름 + 신뢰도 배지
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${userProvider.currentUser?.name ?? '사용자'}님',
                            style: ResponsiveHelper.titleStyle(context).copyWith(
                              color: Colors.white,
                              fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 1.5,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        if (userProvider.currentUser != null)
                          _buildTrustBadge(context, userProvider.currentUser!),
                      ],
                    ),

                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),

                    Text(
                      userProvider.currentUser?.userEmail ?? '',
                      style: ResponsiveHelper.smallStyle(context,
                          color: Colors.white.withValues(alpha: 0.9)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // 메뉴 카드 영역
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
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
                    child: Column(
                      children: [
                        if (userProvider.isSubAdmin)
                          _buildAdminModeBanner(context, userProvider),
                        _buildOnboardingBanner(context, userProvider),
                        Expanded(
                          child: GridView.count(
                            crossAxisCount: 2,
                            childAspectRatio: 0.9,
                            crossAxisSpacing: ResponsiveHelper.spacing(context, 16),
                            mainAxisSpacing: ResponsiveHelper.spacing(context, 16),
                            children: [
                              _buildMenuCard(context,
                                  icon: Icons.search,
                                  title: '공고 찾기',
                                  subtitle: '알바 공고 검색',
                                  color: theme.primaryColor,
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const AllTOListScreen()))),
                              _buildMenuCard(context,
                                  icon: Icons.calendar_month,
                                  title: '근무 스케줄',
                                  subtitle: '일정 한눈에 보기',
                                  color: theme.primaryColor,
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const MyScheduleScreen()))),
                              _buildMenuCard(context,
                                  icon: Icons.access_time_outlined,
                                  title: '출퇴근 체크',
                                  subtitle: '근무 시간 기록',
                                  color: theme.primaryColor,
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const AttendanceCheckScreen()))),
                              _buildMenuCard(context,
                                  icon: Icons.assignment,
                                  title: '내 지원 내역',
                                  subtitle: '지원 현황 확인',
                                  color: theme.primaryColor,
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const MyApplicationsScreen()))),
                              _buildMenuCard(context,
                                  icon: Icons.folder_outlined,
                                  title: '내 계약서',
                                  subtitle: '계약서 서명·확인',
                                  color: AppColors.infoDark,
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const UserContractsScreen()))),
                              _buildMenuCard(context,
                                  icon: Icons.star_rounded,
                                  title: '내 평가 확인',
                                  subtitle: '사업장의 근무 평가',
                                  color: AppColors.warning,
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const MyReviewsScreen()))),
                              _buildMenuCard(context,
                                  icon: Icons.settings_outlined,
                                  title: '설정',
                                  subtitle: '앱 설정',
                                  color: AppColors.grey600,
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const SettingsScreen()))),
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
  }

  Widget _buildMenuCard(BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: Icon(icon, size: ResponsiveHelper.iconSize(context, 32), color: color),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                Text(title,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(subtitle,
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                    textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnboardingBanner(BuildContext context, UserProvider userProvider) {
    final user = userProvider.currentUser;
    if (user == null) return const SizedBox.shrink();
    final missing = <String>[];
    if (!user.isEmailVerified) missing.add('이메일 인증');
    if (user.idCardImageUrl == null) missing.add('신분증');
    if (user.bankbookImageUrl == null) missing.add('통장사본');
    if (user.bankName == null || user.accountNumber == null) missing.add('통장 정보');
    if (missing.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.warningBg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning, width: 1.2),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 22),
        SizedBox(width: ResponsiveHelper.spacing(context, 10)),
        Expanded(child: Text('공고 지원 전 등록 필요: ${missing.join(', ')}',
            style: ResponsiveHelper.smallStyle(context)
                .copyWith(color: AppColors.warning, fontWeight: FontWeight.w600))),
        TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: Text('등록하기',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                  color: AppColors.warning, fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline)),
        ),
      ]),
    );
  }

  Widget _buildAdminModeBanner(BuildContext context, UserProvider userProvider) {
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
      padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [theme.primaryColor, theme.colorScheme.secondary],
            begin: Alignment.centerLeft, end: Alignment.centerRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Icon(Icons.admin_panel_settings_outlined, color: Colors.white,
            size: ResponsiveHelper.iconSize(context, 20)),
        SizedBox(width: ResponsiveHelper.spacing(context, 10)),
        Expanded(child: Text('관리자 권한이 있어요',
            style: ResponsiveHelper.smallStyle(context, color: Colors.white))),
        TextButton(
          onPressed: () => userProvider.toggleAdminMode(),
          style: TextButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 6)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text('관리자 모드',
              style: ResponsiveHelper.smallStyle(context, color: Colors.white)
                  .copyWith(fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _buildTrustBadge(BuildContext context, UserModel user) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 4)),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(user.trustGradeEmoji, style: ResponsiveHelper.bodyStyle(context)),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text('${user.trustScore}점',
            style: ResponsiveHelper.smallStyle(context)
                .copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
