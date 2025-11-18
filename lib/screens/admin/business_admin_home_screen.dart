import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/auth_service.dart';
import '../../utils/dialog_helper.dart';
import 'business_list_screen.dart';
import '../../utils/toast_helper.dart';
import 'admin_create_to_screen.dart';
import 'settings_screen.dart';
import 'integrated_workforce_screen.dart';

/// 사업장 관리자 홈 화면 - 반응형 (항상 2열)
class BusinessAdminHomeScreen extends StatelessWidget {
  const BusinessAdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
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
                                '사업장 관리자',
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
                          SizedBox(height: 8 * scale),
                          Text(
                            '안녕하세요 👋',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8 * scale),
                          Text(
                            '${userProvider.currentUser?.name ?? '관리자'}님',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 4 * scale),
                          Text(
                            userProvider.currentUser?.email ?? '',
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
                            // 1. 사업장 관리
                            _buildMenuCard(
                              context,
                              scale: scale,  // ⭐ scale 전달
                              icon: Icons.business_rounded,
                              title: '사업장 관리',
                              subtitle: '내 사업장 목록',
                              color: Colors.blue,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => BusinessListScreen(),
                                  ),
                                );
                              },
                            ),

                            // 2. TO 생성
                            _buildMenuCard(
                              context,
                              scale: scale,
                              icon: Icons.add_circle_outline,
                              title: 'TO 생성',
                              subtitle: '새 근무 등록',
                              color: Colors.green,
                              onTap: () async {
                                final result = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const AdminCreateTOScreen(),
                                  ),
                                );
                                
                                if (result == true) {
                                  ToastHelper.showSuccess('TO가 생성되었습니다');
                                }
                              },
                            ),

                            // 3. 인력 관리 (통합)
                            _buildMenuCard(
                              context,
                              scale: scale,
                              icon: Icons.groups,
                              title: '인력 관리',
                              subtitle: 'TO 관리 & 현황',
                              color: Colors.purple,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const IntegratedWorkforceScreen(),
                                  ),
                                );
                              },
                            ),

                            // 4. 통계
                            _buildMenuCard(
                              context,
                              scale: scale,
                              icon: Icons.bar_chart_outlined,
                              title: '통계',
                              subtitle: 'TO 현황',
                              color: Colors.teal,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('통계 화면 준비 중입니다')),
                                );
                              },
                            ),

                            // 5. 설정
                            _buildMenuCard(
                              context,
                              scale: scale,
                              icon: Icons.settings_outlined,
                              title: '설정',
                              subtitle: '앱 설정',
                              color: Colors.grey,
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
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 반응형 메뉴 카드
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16 * scale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 아이콘
              Container(
                padding: EdgeInsets.all(16 * scale),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32 * scale,
                  color: color,
                ),
              ),
              SizedBox(height: 12 * scale),
              // 제목
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
              // 부제목
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