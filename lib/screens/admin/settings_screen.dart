import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import 'work_type_management_screen.dart';

/// 설정 화면 (사업장 관리자용)
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: Colors.blue[700],
      ),
      body: ListView(
        children: [
          // 계정 정보 섹션
          _buildSectionHeader('계정 정보'),
          _buildInfoTile(
            icon: Icons.person,
            title: '이름',
            subtitle: userProvider.currentUser?.name ?? '',
          ),
          _buildInfoTile(
            icon: Icons.email,
            title: '이메일',
            subtitle: userProvider.currentUser?.email ?? '',
          ),
          _buildInfoTile(
            icon: Icons.badge,
            title: '권한',
            subtitle: userProvider.currentUser?.isBusinessAdmin == true
                ? '사업장 관리자'
                : '일반 사용자',
          ),

          const Divider(height: 32),

          // 사업장 설정 섹션
          _buildSectionHeader('사업장 설정'),
          _buildMenuTile(
            context,
            icon: Icons.work_outline,
            iconColor: Colors.orange,
            title: '업무 유형 관리',
            subtitle: '사업장의 업무 유형을 설정합니다',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WorkTypeManagementScreen(),
                ),
              );
            },
          ),

          const Divider(height: 32),

          // 앱 정보 섹션
          _buildSectionHeader('앱 정보'),
          _buildInfoTile(
            icon: Icons.info_outline,
            title: '버전',
            subtitle: '1.0.0',
          ),
        ],
      ),
    );
  }

  /// 섹션 헤더
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  /// 정보 표시 타일 (클릭 불가)
  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[600]),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }

  /// 메뉴 타일 (클릭 가능)
  Widget _buildMenuTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }
}