import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Models
import '../../models/core/user_model.dart';

// Providers  
import '../../providers/user_provider.dart';

// Utils
import '../../utils/responsive_helper.dart';

// Screens
import '../business_admin/work_type_management_screen.dart';
import 'document_management_screen.dart';

/// ✨ 통합 설정 화면 (역할별 메뉴 자동 표시)
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('설정'),
      ),
      body: ListView(
        padding: ResponsiveHelper.cardPadding(context),
        children: [
          // ✨ 프로필 카드 (공통)
          _buildProfileCard(context, userProvider),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // ✨ 내 정보 섹션 (공통)
          _buildSectionHeader(context, '내 정보', Icons.person_outline),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          _buildMenuCard(
            context,
            icon: Icons.edit,
            iconColor: Colors.blue,
            title: '프로필 수정',
            subtitle: '이름, 연락처 등 기본 정보 수정',
            onTap: () {
              // TODO: 프로필 수정 화면
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('프로필 수정 화면 (구현 예정)')),
              );
            },
          ),
          
          // ✨ 지원자 전용 메뉴
          if (user?.role == UserRole.USER) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildMenuCard(
              context,
              icon: Icons.folder_special,
              iconColor: Colors.green,
              title: '내 서류 관리',
              subtitle: '신분증, 통장사본 등록 및 수정',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DocumentManagementScreen(),
                  ),
                );
              },
            ),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // ✨ 사업장 관리자 전용 섹션
          if (user?.role == UserRole.BUSINESS_ADMIN) ...[
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
            
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            
            _buildMenuCard(
              context,
              icon: Icons.store,
              iconColor: Colors.purple,
              title: '사업장 정보',
              subtitle: '사업장 정보 확인 및 수정',
              onTap: () {
                // TODO: 사업장 정보 화면
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('사업장 정보 화면 (구현 예정)')),
                );
              },
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          ],

          // ✨ 슈퍼 관리자 전용 섹션
          if (user?.role == UserRole.SUPER_ADMIN) ...[
            _buildSectionHeader(context, '관리자 메뉴', Icons.admin_panel_settings),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            
            _buildMenuCard(
              context,
              icon: Icons.people,
              iconColor: Colors.red,
              title: '전체 사용자 관리',
              subtitle: '모든 사용자 정보 확인 및 관리',
              onTap: () {
                // TODO: 사용자 관리 화면
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('사용자 관리 화면 (구현 예정)')),
                );
              },
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            
            _buildMenuCard(
              context,
              icon: Icons.business_center,
              iconColor: Colors.deepPurple,
              title: '전체 사업장 관리',
              subtitle: '모든 사업장 정보 확인 및 관리',
              onTap: () {
                // TODO: 사업장 관리 화면
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('사업장 관리 화면 (구현 예정)')),
                );
              },
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          ],

          // ✨ 알림 섹션 (공통)
          _buildSectionHeader(context, '알림', Icons.notifications_outlined),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          _buildMenuCard(
            context,
            icon: Icons.notifications_active,
            iconColor: Colors.amber,
            title: '알림 설정',
            subtitle: '푸시 알림 및 이메일 알림 설정',
            onTap: () {
              // TODO: 알림 설정 화면
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('알림 설정 화면 (구현 예정)')),
              );
            },
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // ✨ 앱 정보 섹션 (공통)
          _buildSectionHeader(context, '앱 정보', Icons.info_outline),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          _buildInfoCard(
            context,
            items: [
              {'icon': Icons.phone_android, 'title': '앱 버전', 'value': '1.0.0'},
              {'icon': Icons.update, 'title': '최신 업데이트', 'value': '2024.11.21'},
              {'icon': Icons.policy, 'title': '개인정보 처리방침', 'value': '보기'},
              {'icon': Icons.description, 'title': '이용약관', 'value': '보기'},
            ],
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // ✨ 로그아웃 버튼 (공통)
          _buildLogoutButton(context, userProvider),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        ],
      ),
    );
  }

  /// ✨ 세련된 프로필 카드
  Widget _buildProfileCard(BuildContext context, UserProvider userProvider) {
    final theme = Theme.of(context);
    final user = userProvider.currentUser;
    
    // 역할별 색상
    Color getRoleColor() {
      switch (user?.role) {
        case UserRole.SUPER_ADMIN:
          return Colors.red;
        case UserRole.BUSINESS_ADMIN:
          return Colors.blue;
        case UserRole.USER:
        default:
          return Colors.green;
      }
    }
    
    // 역할별 이름
    String getRoleName() {
      switch (user?.role) {
        case UserRole.SUPER_ADMIN:
          return '슈퍼 관리자';
        case UserRole.BUSINESS_ADMIN:
          return '사업장 관리자';
        case UserRole.USER:
        default:
          return '지원자';
      }
    }
    
    final roleColor = getRoleColor();
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            roleColor,
            roleColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: roleColor.withOpacity(0.3),
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
          
          // 이메일/아이디
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
                  Icons.account_circle,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: Colors.white,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Flexible(
                  child: Text(
                    user?.username ?? user?.email ?? '',
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  user?.role == UserRole.SUPER_ADMIN
                      ? Icons.verified_user
                      : user?.role == UserRole.BUSINESS_ADMIN
                          ? Icons.admin_panel_settings
                          : Icons.person,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: roleColor,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  getRoleName(),
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: roleColor,
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

  /// ✨ 로그아웃 버튼
  Widget _buildLogoutButton(BuildContext context, UserProvider userProvider) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('로그아웃'),
                content: Text('정말 로그아웃하시겠습니까?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('취소'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: Text('로그아웃'),
                  ),
                ],
              ),
            );

            if (confirmed == true) {
              await userProvider.signOut();
            }
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.logout,
                  color: Colors.red,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Text(
                  '로그아웃',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}