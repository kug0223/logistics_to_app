import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import 'business_list_screen.dart';  // ⭐ 같은 admin 폴더!

/// 사업장 관리자 홈 화면 (USER 홈과 동일한 레이아웃)
class BusinessAdminHomeScreen extends StatelessWidget {
  const BusinessAdminHomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    // ⭐ Consumer 패턴 사용 (다른 홈 화면들과 동일)
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        return Scaffold(
          backgroundColor: Colors.blue[700],
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 상단 헤더 (지원자 홈과 동일)
                Container(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '사업장 관리자',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout, color: Colors.white),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('로그아웃'),
                                  content: const Text('로그아웃 하시겠습니까?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('취소'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('로그아웃'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true) {
                                await authService.signOut();
                                if (context.mounted) {
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const LoginScreen(),
                                    ),
                                    (route) => false,
                                  );
                                }
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '안녕하세요 👋',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${userProvider.currentUser?.name ?? '관리자'}님',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userProvider.currentUser?.email ?? '',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // 메뉴 카드들 (지원자 홈과 동일한 레이아웃)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                      ),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      children: [
                        // 1. 사업장 관리
                        _buildMenuCard(
                          context,
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
                          icon: Icons.add_circle_outline,
                          title: 'TO 생성',
                          subtitle: '새 근무 등록',
                          color: Colors.green,
                          onTap: () {
                            // TODO: AdminCreateTOScreen으로 이동
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('TO 생성 화면 준비 중입니다')),
                            );
                          },
                        ),

                        // 3. TO 관리
                        _buildMenuCard(
                          context,
                          icon: Icons.assignment_outlined,
                          title: 'TO 관리',
                          subtitle: '내 TO 조회',
                          color: Colors.orange,
                          onTap: () {
                            // TODO: 내 TO 목록 화면으로 이동
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('TO 관리 화면 준비 중입니다')),
                            );
                          },
                        ),

                        // 4. 지원자 관리
                        _buildMenuCard(
                          context,
                          icon: Icons.people_outline,
                          title: '지원자 관리',
                          subtitle: '승인/거절',
                          color: Colors.purple,
                          onTap: () {
                            // TODO: 지원자 관리 화면으로 이동
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('지원자 관리 화면 준비 중입니다')),
                            );
                          },
                        ),

                        // 5. 통계
                        _buildMenuCard(
                          context,
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

                        // 6. 설정
                        _buildMenuCard(
                          context,
                          icon: Icons.settings_outlined,
                          title: '설정',
                          subtitle: '앱 설정',
                          color: Colors.grey,
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('설정 화면 준비 중입니다')),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 메뉴 카드 위젯 (지원자 홈과 동일)
  Widget _buildMenuCard(
    BuildContext context, {
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
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 아이콘
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: color,
                ),
              ),
              const SizedBox(height: 12),
              // 제목
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              // 부제목
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}