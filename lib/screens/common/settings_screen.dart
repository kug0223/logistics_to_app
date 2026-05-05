import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Models
import '../../models/core/user_model.dart';

// Providers  
import '../../providers/user_provider.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/navigation_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/badge_display_widget.dart';
import '../../widgets/dialogs/restart_program_dialog.dart';
import '../../widgets/dialogs/trust_score_info_dialog.dart';

// Screens
import '../business_admin/work_type_management_screen.dart';
import 'document_management_screen.dart';
import 'profile_edit_screen.dart';
import '../business_admin/business_list_screen.dart';

// Services
import '../../services/firestore_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/fcm_service.dart';

// Utils
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../theme/app_colors.dart';

/// ✨ 통합 설정 화면 (역할별 메뉴 자동 표시)
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isPushEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationStatus();
  }

  /// 알림 상태 로드
  Future<void> _loadNotificationStatus() async {
    final userProvider = context.read<UserProvider>();
    final userId = userProvider.currentUser?.uid;
    
    if (userId != null) {
      // Firestore에서 fcmToken 존재 여부로 판단
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      final hasFcmToken = doc.data()?['fcmToken'] != null;
      
      if (mounted) {
        setState(() {
          _isPushEnabled = hasFcmToken;
          _isLoading = false;
        });
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  /// 푸시 알림 토글
  Future<void> _togglePushNotification(bool value) async {
    setState(() => _isLoading = true);
    
    try {
      final userProvider = context.read<UserProvider>();
      final userId = userProvider.currentUser?.uid;
      
      if (userId == null) return;
      
      if (value) {
        // 알림 켜기 → FCM 초기화
        await FCMService().initialize(userId);
        ToastHelper.showSuccess('푸시 알림이 활성화되었습니다');
      } else {
        // 알림 끄기 → FCM 토큰 삭제
        await FCMService().clearToken();
        ToastHelper.showSuccess('푸시 알림이 비활성화되었습니다');
      }
      
      setState(() => _isPushEnabled = value);
    } catch (e) {
      debugPrint('❌ 알림 설정 변경 실패: $e');
      ToastHelper.showError('알림 설정 변경에 실패했습니다');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final user = userProvider.currentUser;

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
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileEditScreen(),
                ),
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
                NavigationHelper.push<bool>(
                  context,
                  destination: const DocumentManagementScreen(),
                );
              },
            ),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // ✨ 사업장 관리자 전용 섹션
          if (user?.role == UserRole.BUSINESS_ADMIN) ...[
            _buildSectionHeader(context, '사업장 설정', Icons.business),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            // ✅ 추가: 내 서류 관리 (사업자등록증)
            _buildMenuCard(
              context,
              icon: Icons.description,
              iconColor: Colors.teal,
              title: '내 서류 관리',
              subtitle: '사업자등록증 관리',
              onTap: () {
                NavigationHelper.push<bool>(
                  context,
                  destination: const DocumentManagementScreen(),
                );
              },
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            
            // 메뉴 onTap 수정
            _buildMenuCard(
              context,
              icon: Icons.business,
              iconColor: Colors.purple,
              title: '사업장 정보',
              subtitle: '내 사업장 관리',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BusinessListScreen(),
                  ),
                );
              },
            ),
            
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
            
            // 🔧 개발자 도구 섹션
            _buildSectionHeader(context, '개발자 도구', Icons.developer_mode),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            
            _buildMenuCard(
              context,
              icon: Icons.sync,
              iconColor: Colors.orange,
              title: 'Application 마이그레이션',
              subtitle: 'workDetailId/toId/groupId 채우기',
              onTap: () => _runApplicationMigration(context),
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          ],


          // ✨ 알림 섹션 (공통)
          _buildSectionHeader(context, '알림', Icons.notifications_outlined),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 푸시 알림 토글
          _buildNotificationToggleCard(context),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 시스템 알림 설정
          _buildMenuCard(
            context,
            icon: Icons.settings_applications,
            iconColor: AppColors.grey600,
            title: '시스템 알림 설정',
            subtitle: '기기의 알림 설정을 변경합니다',
            onTap: () async {
              await openAppSettings();
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
    
    // ⭐ Theme에서 자동으로 역할별 색상 가져옴
    final roleColor = theme.primaryColor;
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            roleColor,
            roleColor.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: roleColor.withValues(alpha: 0.3),
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
              color: Colors.white.withValues(alpha: 0.2),
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
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          
          // 아이디
          Text(
            '@${user?.username ?? 'username'}',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 역할 뱃지
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 6),
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1,
              ),
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
                  color: Colors.white,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  // ⭐ CommonWidgets.getRoleName() 사용
                  CommonWidgets.getRoleName(user?.roleString ?? 'USER'),
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // 🆕 지원자 신뢰도 섹션
          if (user?.role == UserRole.USER) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // 신뢰도 점수
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        user!.trustGradeEmoji,
                        style: TextStyle(fontSize: ResponsiveHelper.spacing(context, 24)),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        '신뢰도 ${user.trustScore}점',
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 8),
                          vertical: ResponsiveHelper.spacing(context, 2),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          user.trustGrade,
                          style: ResponsiveHelper.smallStyle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // 🆕 신뢰도 설명 버튼
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      GestureDetector(
                        onTap: () => TrustScoreInfoDialog.show(context),
                        child: Container(
                          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.help_outline,
                            size: ResponsiveHelper.iconSize(context, 16),
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  // 근태 통계
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatItem(context, '근무', '${user.totalWorkDays}일'),
                      _buildStatItem(context, '평점', user.averageRating.toStringAsFixed(1)),
                      _buildStatItem(context, '지각', '${user.lateCount}회'),
                      _buildStatItem(context, '노쇼', '${user.noShowCount}회'),
                    ],
                  ),
                  // 🆕 배지 섹션
                  if (user.badges.isNotEmpty) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    Row(
                      children: [
                        Icon(
                          Icons.emoji_events,
                          size: ResponsiveHelper.iconSize(context, 16),
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                        Text(
                          '획득 배지',
                          style: ResponsiveHelper.smallStyle(context).copyWith(
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    BadgeDisplayWidget(
                      badgeIds: user.badges,
                      maxDisplay: 5,
                      compact: true,
                    ),
                  ],
                  
                  // 🆕 재시작 프로그램 버튼 (신뢰도 50점 미만일 때 표시)
                  if (user.trustScore < 50) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    Divider(color: Colors.white.withValues(alpha: 0.2), height: 1),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    InkWell(
                      onTap: () => _showRestartProgramDialog(context, user),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 12),
                          vertical: ResponsiveHelper.spacing(context, 10),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.refresh,
                              size: ResponsiveHelper.iconSize(context, 18),
                              color: Colors.white,
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            Text(
                              '재시작 프로그램 신청',
                              style: ResponsiveHelper.smallStyle(context).copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

 /// 🆕 재시작 프로그램 다이얼로그 표시
  Future<void> _showRestartProgramDialog(BuildContext context, UserModel user) async {
    final result = await showRestartProgramDialog(
      context,
      userId: user.uid,
      currentScore: user.trustScore,
      noShowCount: user.noShowCount,
      lateCount: user.lateCount,
      onSuccess: () {
        // 사용자 정보 새로고침
        context.read<UserProvider>().refreshCurrentUser();
      },
    );
    
    if (result == true) {
      // 성공 시 화면 새로고침
      setState(() {});
    }
  }

 /// 🆕 통계 아이템 (신뢰도 카드용)
  Widget _buildStatItem(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(context).copyWith(
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ],
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
            color: theme.primaryColor.withValues(alpha: 0.1),
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
            color: Colors.grey.withValues(alpha: 0.1),
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
                        iconColor.withValues(alpha: 0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: iconColor.withValues(alpha: 0.3),
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
                          color: AppColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 화살표
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
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
            color: Colors.grey.withValues(alpha: 0.1),
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
                          color: theme.primaryColor.withValues(alpha: 0.1),
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
                                color: AppColors.grey600,
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
  /// ✨ 알림 토글 카드
  Widget _buildNotificationToggleCard(BuildContext context) {
    final theme = Theme.of(context);
    const iconColor = Colors.amber;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: ResponsiveHelper.cardPadding(context),
          child: Row(
            children: [
              // 아이콘 (buildMenuCard와 동일한 스타일)
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      iconColor,
                      iconColor.withValues(alpha: 0.8),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.notifications_active,
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
                      '푸시 알림',
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      _isPushEnabled ? '알림을 받고 있습니다' : '알림이 꺼져 있습니다',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: AppColors.grey600,
                      ),
                    ),
                  ],
                ),
              ),
              
              // 토글 스위치 (화살표 대신)
              _isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.primaryColor,
                      ),
                    )
                  : Switch(
                      value: _isPushEnabled,
                      onChanged: _togglePushNotification,
                      activeColor: theme.primaryColor,
                    ),
            ],
          ),
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
            color: Colors.red.withValues(alpha: 0.1),
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
// ... _buildMenuCard 메서드 끝나는 부분

  /// 🔄 Application 마이그레이션 실행
  void _runApplicationMigration(BuildContext context) async {
    // 확인 다이얼로그
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: 'Application 마이그레이션',
      message: '기존 지원서에 누락된 workDetailId, toId, groupId를 채웁니다.\n\n'
               '⚠️ 데이터가 많으면 시간이 걸릴 수 있습니다.\n'
               '계속하시겠습니까?',
      confirmText: '실행',
      cancelText: '취소',
      icon: Icons.sync,
      iconColor: Colors.orange,
    );

    if (!confirmed) return;

    // 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                '마이그레이션 진행 중...\n잠시만 기다려주세요.',
                textAlign: TextAlign.center,
                style: ResponsiveHelper.bodyStyle(context),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      // 마이그레이션 실행
      final result = await FirestoreService().migrateApplicationWorkDetailIds();
      
      // 로딩 닫기
      if (context.mounted) Navigator.pop(context);

      // 결과 표시
      final migrated = result['migrated'] ?? 0;
      final skipped = result['skipped'] ?? 0;
      final failed = result['failed'] ?? 0;

      if (context.mounted) {
        if (failed == -1) {
          ToastHelper.showError('마이그레이션 실패');
        } else {
          await DialogHelper.showInfo(
            context,
            title: '마이그레이션 완료',
            message: '✅ 마이그레이션: $migrated개\n'
                     '⏭️ 스킵 (이미 있음): $skipped개\n'
                     '❌ 실패: $failed개',
          );
        }
      }
    } catch (e) {
      // 로딩 닫기
      if (context.mounted) Navigator.pop(context);
      ToastHelper.showError('마이그레이션 오류: $e');
    }
  }
}
