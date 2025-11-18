import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';
import 'admin_all_businesses_screen.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';

/// 최고관리자(SUPER_ADMIN) 홈 화면 - 반응형 (항상 2열)
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        final user = userProvider.currentUser;
        
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.primary,
          body: SafeArea(
            child: LayoutBuilder(  // ⭐ 전체를 LayoutBuilder로 감싸기
              builder: (context, constraints) {
                final screenWidth = MediaQuery.of(context).size.width;
                final scale = screenWidth < 360 ? 0.85 : screenWidth < 400 ? 0.9 : 1.0;
                final spacing = screenWidth < 360 ? 12.0 : 16.0;
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 상단 헤더 - 반응형
                    Container(
                      padding: EdgeInsets.all(24 * scale),  // ⭐ 스케일 적용
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '최고관리자',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16 * scale,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.logout, color: Colors.white),
                                iconSize: 24 * scale,  // ⭐ 아이콘 크기
                                padding: EdgeInsets.all(8 * scale),
                                constraints: BoxConstraints(
                                  minWidth: 40 * scale,
                                  minHeight: 40 * scale,
                                ),
                                onPressed: () async {
                                  final confirmed = await DialogHelper.showLogoutConfirm(context);

                                  if (confirmed && context.mounted) {
                                    context.read<ThemeProvider>().reset();
                                    await userProvider.signOut();
                                  }
                                },
                              ),
                            ],
                          ),
                          SizedBox(height: 16 * scale),
                          Text(
                            '안녕하세요! 👋',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 18 * scale,
                            ),
                          ),
                          SizedBox(height: 8 * scale),
                          Text(
                            '${user?.name ?? '관리자'}님',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4 * scale),
                          Text(
                            user?.email ?? '',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14 * scale,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 32 * scale),  // ⭐ 스케일 적용

                    // 메뉴 카드들 - 항상 2열, 크기만 반응형
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(32),
                            topRight: Radius.circular(32),
                          ),
                        ),
                        padding: EdgeInsets.all(24 * scale),  // ⭐ 스케일 적용
                        child: GridView.count(
                          crossAxisCount: 2,  // ⭐ 항상 2열 고정
                          crossAxisSpacing: spacing,
                          mainAxisSpacing: spacing,
                          children: [
                            // 1. 모든 사업장 관리
                            _buildMenuCard(
                              context,
                              scale: scale,  // ⭐ scale 전달
                              icon: Icons.business_center,
                              title: '모든 사업장',
                              subtitle: '전체 사업장 관리',
                              color: Colors.purple,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AllBusinessesScreen(),
                                  ),
                                );
                              },
                            ),

                            // 2. 전체 TO 모니터링
                            _buildMenuCard(
                              context,
                              scale: scale,
                              icon: Icons.dashboard_outlined,
                              title: 'TO 모니터링',
                              subtitle: '전체 TO 현황',
                              color: Colors.blue,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('TO 모니터링 기능은 준비 중입니다')),
                                );
                              },
                            ),

                            // 3. 사용자 관리
                            _buildMenuCard(
                              context,
                              scale: scale,
                              icon: Icons.people_outline,
                              title: '사용자 관리',
                              subtitle: '회원 관리',
                              color: Colors.green,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('사용자 관리 기능은 준비 중입니다')),
                                );
                              },
                            ),

                            // 4. 통계 대시보드
                            _buildMenuCard(
                              context,
                              scale: scale,
                              icon: Icons.analytics_outlined,
                              title: '통계',
                              subtitle: '전체 통계 분석',
                              color: Colors.orange,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('통계 기능은 준비 중입니다')),
                                );
                              },
                            ),

                            // 5. 설정
                            _buildMenuCard(
                              context,
                              scale: scale,
                              icon: Icons.settings_outlined,
                              title: '설정',
                              subtitle: '시스템 설정',
                              color: Colors.grey,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('설정 기능은 준비 중입니다')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // 반응형 메뉴 카드
  Widget _buildMenuCard(
    BuildContext context, {
    required double scale,  // ⭐ scale 파라미터 추가
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(16 * scale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(16 * scale),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 32 * scale,
                  color: color,
                ),
              ),
              SizedBox(height: 12 * scale),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16 * scale,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 4 * scale),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12 * scale,
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
    );
  }
}