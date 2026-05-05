import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import 'all_to_list_screen.dart';
import 'my_schedule_screen.dart';
import 'attendance_check_screen.dart';
import 'my_applications_screen.dart';
import '../common/settings_screen.dart';
import '../common/notification_screen.dart';
import '../../widgets/common/notification_badge.dart';
import '../../models/core/user_model.dart';
import '../../theme/app_colors.dart';

/// 일반 사용자 홈 화면 - 세련된 디자인
class UserHomeScreen extends StatelessWidget {
  const UserHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final theme = Theme.of(context);

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
                        // 🆕 신뢰도 배지
                        if (userProvider.currentUser != null)
                          _buildTrustBadge(context, userProvider.currentUser!),
                      ],
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
                    color: AppColors.grey50,
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
                        // 1. 근무 지원하기
                        _buildMenuCard(
                          context,
                          icon: Icons.warehouse_rounded,
                          title: '근무 지원하기',
                          subtitle: '사업장 선택',
                          color: theme.primaryColor,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AllTOListScreen(),
                              ),
                            );
                          },
                        ),

                        // 2. 근무 스케줄
                        _buildMenuCard(
                          context,
                          icon: Icons.calendar_month,
                          title: '근무 스케줄',
                          subtitle: '일정 한눈에 보기',
                          color: theme.primaryColor.withOpacity(0.8),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MyScheduleScreen(),
                              ),
                            );
                          },
                        ),

                        // 3. 출퇴근 체크
                        _buildMenuCard(
                          context,
                          icon: Icons.access_time_outlined,
                          title: '출퇴근 체크',
                          subtitle: '근무 시간 기록',
                          color: theme.primaryColor.withOpacity(0.7),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AttendanceCheckScreen(),
                              ),
                            );
                          },
                        ),

                        // 4. 내 지원 내역
                        _buildMenuCard(
                          context,
                          icon: Icons.assignment,
                          title: '내 지원 내역',
                          subtitle: '지원 현황 확인',
                          color: theme.primaryColor.withOpacity(0.6),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const MyApplicationsScreen(),
                              ),
                            );
                          },
                        ),

                        // 5. 설정
                        _buildMenuCard(
                          context,
                          icon: Icons.settings_outlined,
                          title: '설정',
                          subtitle: '앱 설정',
                          color: AppColors.grey600!,
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
                    color: AppColors.grey600,
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
  /// 🆕 신뢰도 배지
  Widget _buildTrustBadge(BuildContext context, UserModel user) {
    final score = user.trustScore;
    final emoji = user.trustGradeEmoji;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            emoji,
            style: TextStyle(fontSize: ResponsiveHelper.spacing(context, 14)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            '$score점',
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
