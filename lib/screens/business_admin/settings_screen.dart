import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/responsive_helper.dart';
import 'work_type_management_screen.dart';

/// ✨ 세련된 설정 화면 (사업장 관리자용)
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      // ✨ 깔끔한 단색 AppBar
      appBar: AppBar(
        title: Text('설정'),
      ),
      // ✨ 흰색 배경
      body: ListView(
          padding: ResponsiveHelper.cardPadding(context),
          children: [
            // ✨ 프로필 카드
            _buildProfileCard(context, userProvider),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),

            // ✨ 사업장 설정 섹션
            _buildSectionHeader(context, '사업장 설정', Icons.business),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildMenuCard(
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

            SizedBox(height: ResponsiveHelper.spacing(context, 24)),

            // ✨ 앱 정보 섹션
            _buildSectionHeader(context, '앱 정보', Icons.info_outline),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildInfoCard(
              context,
              items: [
                {'icon': Icons.phone_android, 'title': '앱 버전', 'value': '1.0.0'},
                {'icon': Icons.update, 'title': '최신 업데이트', 'value': '2024.11.20'},
              ],
            ),
          ],
        ),
    );
  }

  /// ✨ 세련된 프로필 카드
  Widget _buildProfileCard(BuildContext context, UserProvider userProvider) {
    final theme = Theme.of(context);
    final user = userProvider.currentUser;
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor,
            theme.primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.primaryColor.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // 프로필 아이콘
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person,
              size: ResponsiveHelper.iconSize(context, 48),
              color: Colors.white,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 이름
          Text(
            user?.name ?? '사용자',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 이메일
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.email,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: Colors.white,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Flexible(
                  child: Text(
                    user?.email ?? '',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 권한 배지
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: user?.isBusinessAdmin == true
                  ? Colors.amber.withOpacity(0.9)
                  : Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: (user?.isBusinessAdmin == true ? Colors.amber : Colors.white)
                      .withOpacity(0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  user?.isBusinessAdmin == true ? Icons.admin_panel_settings : Icons.person,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: user?.isBusinessAdmin == true ? Colors.black87 : Colors.white,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  user?.isBusinessAdmin == true ? '사업장 관리자' : '일반 사용자',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: user?.isBusinessAdmin == true ? Colors.black87 : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 세련된 섹션 헤더
  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: theme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: theme.primaryColor,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Text(
          title,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// ✨ 세련된 메뉴 카드
  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Row(
              children: [
                // 아이콘
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        iconColor,
                        iconColor.withOpacity(0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: iconColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: ResponsiveHelper.iconSize(context, 28),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                
                // 텍스트
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        subtitle,
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 화살표
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: iconColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ✨ 세련된 정보 카드
  Widget _buildInfoCard(
    BuildContext context, {
    required List<Map<String, dynamic>> items,
  }) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: List.generate(
          items.length,
          (index) {
            final item = items[index];
            final isLast = index == items.length - 1;
            
            return Column(
              children: [
                Padding(
                  padding: ResponsiveHelper.cardPadding(context),
                  child: Row(
                    children: [
                      // 아이콘
                      Container(
                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          item['icon'] as IconData,
                          color: theme.primaryColor,
                          size: ResponsiveHelper.iconSize(context, 24),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                      
                      // 텍스트
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['title'] as String,
                              style: ResponsiveHelper.bodyStyle(
                                context,
                                color: Colors.grey[600],
                              ),
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                            Text(
                              item['value'] as String,
                              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Divider(
                    height: 1,
                    indent: ResponsiveHelper.spacing(context, 16),
                    endIndent: ResponsiveHelper.spacing(context, 16),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}