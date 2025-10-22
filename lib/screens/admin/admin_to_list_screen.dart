import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import './admin_to_list_screen.dart';
import './center_management_screen.dart';

/// 관리자 홈 화면 (메뉴 카드 방식)
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('관리자 모드'),
        backgroundColor: Colors.purple.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirm = await showDialog<bool>(
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
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('로그아웃'),
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                await context.read<UserProvider>().signOut();
                if (context.mounted) {
                  Navigator.of(context).pushReplacementNamed('/login');
                }
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 헤더
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.purple.shade700,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '환영합니다, ${userProvider.currentUser?.displayName ?? '관리자'}님',
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

            // 메뉴 카드들
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  // 1. TO 관리
                  _buildMenuCard(
                    context,
                    icon: Icons.assignment_outlined,
                    title: 'TO 관리',
                    subtitle: '근무 오더 조회/생성',
                    color: Colors.purple,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AdminTOListScreen(),
                        ),
                      );
                    },
                  ),
                  
                  // 2. 사업장 관리
                  // ✅ 🆕 CenterManagementScreen으로 변경 (본인 사업장만 보임)
                  _buildMenuCard(
                    context,
                    icon: Icons.business_outlined,
                    title: '사업장 관리',
                    subtitle: '내 사업장 정보 관리',
                    color: Colors.blue,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CenterManagementScreen(),
                        ),
                      );
                    },
                  ),
                  
                  // 3. 파트 관리
                  _buildMenuCard(
                    context,
                    icon: Icons.category_outlined,
                    title: '파트 관리',
                    subtitle: '업무 파트 등록',
                    color: Colors.teal,
                    onTap: () {
                      // TODO: 파트 관리 화면으로 이동
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('준비 중입니다')),
                      );
                    },
                  ),
                  
                  // 4. 통계
                  _buildMenuCard(
                    context,
                    icon: Icons.bar_chart_outlined,
                    title: '통계',
                    subtitle: 'TO 및 지원자 현황',
                    color: Colors.orange,
                    onTap: () {
                      // TODO: 통계 화면으로 이동
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('준비 중입니다')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
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
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: color.shade700,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
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