import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import './admin_to_list_screen.dart';
import './center_management_screen.dart'; // ✅ 수정: center_form_screen → center_management_screen

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
                      child: const Text('로그아웃'),
                    ),
                  ],
                ),
              );

              if (confirm == true && context.mounted) {
                await userProvider.signOut();
              }
            },
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 환영 메시지
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.purple.shade700,
                      Colors.purple.shade500,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.admin_panel_settings,
                          color: Colors.white,
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Text(
                          '관리자 모드',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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

              // 메뉴 카드들
              Expanded(
                child: GridView.count(
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
                            builder: (context) => AdminTOListScreen(),
                          ),
                        );
                      },
                    ),
                    
                    // 2. 사업장 관리
                    _buildMenuCard(
                      context,
                      icon: Icons.business_outlined,
                      title: '사업장 관리',
                      subtitle: '센터 정보 등록',
                      color: Colors.blue,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            // ✅ 수정: CenterFormScreen() → CenterManagementScreen()
                            builder: (context) => CenterManagementScreen(),
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
                    
                    // 4. 사용자 관리
                    _buildMenuCard(
                      context,
                      icon: Icons.people_outlined,
                      title: '사용자 관리',
                      subtitle: '직원 계정 관리',
                      color: Colors.orange,
                      onTap: () {
                        // TODO: 사용자 관리 화면으로 이동
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('준비 중입니다')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 메뉴 카드 위젯
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
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: color,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
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