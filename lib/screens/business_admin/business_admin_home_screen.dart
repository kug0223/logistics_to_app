import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';

// Services
import '../../services/auth_service.dart';

// Utils
import '../../utils/dialog_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

// Screens
import '../common/settings_screen.dart';
import 'to_management/create_to_screen.dart';
import 'workforce_management/integrated_workforce_screen.dart';
import '../common/notification_screen.dart';
import '../../widgets/common/notification_badge.dart';
import 'admin_review_list_screen.dart';

/// 사업장 관리자 홈 화면 - 세련된 디자인
class BusinessAdminHomeScreen extends StatelessWidget {
  const BusinessAdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final theme = Theme.of(context);

    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.primaryColor,
                  theme.primaryColor.withOpacity(0.85),
                ],
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
                      vertical: ResponsiveHelper.spacing(context, 20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 상단 바 (역할 + 로그아웃)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // ALfit 로고 + 역할
                            Row(
                              children: [
                                // ALfit 로고 + 점 (오른쪽 위)
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Text(
                                      'ALfit',
                                      style: TextStyle(
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
                                          color: Colors.white.withOpacity(0.8),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                                // 역할 뱃지
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ResponsiveHelper.spacing(context, 10),
                                    vertical: ResponsiveHelper.spacing(context, 5),
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.business,
                                        color: Colors.white,
                                        size: ResponsiveHelper.iconSize(context, 14),
                                      ),
                                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                      Text(
                                        '사업장',
                                        style: ResponsiveHelper.tinyStyle(
                                          context,
                                          color: Colors.white,
                                        ).copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            // 🔔 알림 + 로그아웃 버튼
                            Row(
                              children: [
                                // 알림 버튼
                                NotificationBadge(
                                  child: Material(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const NotificationScreen(),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                                        child: Icon(
                                          Icons.notifications_outlined,
                                          color: Colors.white,
                                          size: ResponsiveHelper.iconSize(context, 24),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                // 로그아웃 버튼
                                Material(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
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
                          ],
                        ),
                        
                        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                        
                        // 인사말
                        Text(
                          '안녕하세요! 👋',
                          style: ResponsiveHelper.bodyStyle(
                            context,
                            color: Colors.white.withOpacity(0.95),
                          ),
                        ),
                        
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        
                        // 사용자 이름
                        Text(
                          '${userProvider.currentUser?.name ?? '관리자'}님',
                          style: ResponsiveHelper.titleStyle(context).copyWith(
                            color: Colors.white,
                            fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                        
                        // 이메일
                        Text(
                          userProvider.currentUser?.userEmail ?? '',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: Colors.white.withOpacity(0.9),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  
                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                  // 메뉴 카드 영역
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
                        child: GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: ResponsiveHelper.spacing(context, 16),
                          mainAxisSpacing: ResponsiveHelper.spacing(context, 16),
                          children: [
                            // 1. TO 생성
                            _buildMenuCard(
                              context,
                              icon: Icons.add_circle_outline,
                              title: 'TO 생성',
                              subtitle: '새 근무 등록',
                              color: theme.primaryColor.withOpacity(0.8),
                              onTap: () async {
                                await NavigationHelper.push<bool>(
                                  context,
                                  destination: const AdminCreateTOScreen(),
                                  onReturn: (result) {
                                    if (result == true) {
                                      ToastHelper.showSuccess('TO가 생성되었습니다');
                                    }
                                  },
                                );
                              },
                            ),

                            // 2. 인력 관리 (통합)
                            _buildMenuCard(
                              context,
                              icon: Icons.groups,
                              title: '인력 관리',
                              subtitle: 'TO 관리 & 현황',
                              color: theme.primaryColor.withOpacity(0.7),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const IntegratedWorkforceScreen(),
                                  ),
                                );
                              },
                            ),

                            // 3. 통계
                            _buildMenuCard(
                              context,
                              icon: Icons.bar_chart_outlined,
                              title: '통계',
                              subtitle: 'TO 현황',
                              color: theme.primaryColor.withOpacity(0.6),
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('통계 화면 준비 중입니다')),
                                );
                              },
                            ),
                            // 3. 리뷰 관리
                            _buildMenuCard(
                              context,
                              icon: Icons.rate_review_outlined,
                              title: '리뷰 관리',
                              subtitle: '평가 작성/조회',
                              color: theme.primaryColor.withOpacity(0.6),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AdminReviewListScreen(),
                                  ),
                                );
                              },
                            ),

                            // 4. 설정
                            _buildMenuCard(
                              context,
                              icon: Icons.settings_outlined,
                              title: '설정',
                              subtitle: '앱 설정',
                              color: Colors.grey[600]!,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SettingsScreen(),
                                  ),
                                );
                              },
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

  /// 세련된 메뉴 카드 (단색 버전)
  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 아이콘
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: ResponsiveHelper.iconSize(context, 32),
                    color: color,
                  ),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                
                // 제목
                Text(
                  title,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                
                // 부제목
                Text(
                  subtitle,
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: Colors.grey[600],
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