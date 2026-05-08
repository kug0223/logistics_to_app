import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Models
import '../../models/core/user_model.dart';

// Providers
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';

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
import '../../services/auth_service.dart';
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
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadNotificationStatus();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  /// 알림 상태 로드
  Future<void> _loadNotificationStatus() async {
    final userProvider = context.read<UserProvider>();
    final userId = userProvider.currentUser?.uid;

    if (userId != null) {
      // 시스템 권한 + Firestore fcmToken 둘 다 확인
      final permissionStatus = await Permission.notification.status;
      final systemGranted = permissionStatus.isGranted;

      bool hasFcmToken = false;
      if (systemGranted) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        hasFcmToken = doc.data()?['fcmToken'] != null;
      }

      if (mounted) {
        setState(() {
          _isPushEnabled = systemGranted && hasFcmToken;
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
        // 알림 켜기 → 시스템 권한 먼저 확인
        final permissionStatus = await Permission.notification.status;
        if (permissionStatus.isDenied) {
          await Permission.notification.request();
        }
        final granted = await Permission.notification.isGranted;
        if (!granted) {
          // 시스템에서 거부된 경우 시스템 설정으로 안내
          if (mounted) {
            ToastHelper.showWarning('기기 설정에서 알림 권한을 허용해주세요');
            await openAppSettings();
          }
          setState(() => _isLoading = false);
          return;
        }
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
            iconColor: theme.primaryColor,
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

          // 이메일 인증 카드
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _buildEmailVerificationCard(context, user),

          // ✨ 지원자 전용 메뉴
          if (user?.role == UserRole.USER) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildMenuCard(
              context,
              icon: Icons.folder_special,
              iconColor: AppColors.successDark,
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
              iconColor: AppColors.successDark,
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
              iconColor: AppColors.purpleDark,
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
              iconColor: AppColors.warningDark,
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
              iconColor: AppColors.errorDark,
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
              iconColor: AppColors.purpleDark,
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
              iconColor: AppColors.warningDark,
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
              {'icon': Icons.phone_android, 'title': '앱 버전', 'value': _appVersion.isEmpty ? '...' : _appVersion},
            ],
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // ✨ 로그아웃 버튼 (공통)
          _buildLogoutButton(context, userProvider),

          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 회원탈퇴
          _buildDeleteAccountButton(context, userProvider),

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

  // ━━━ 이메일 인증 ━━━

  Widget _buildEmailVerificationCard(BuildContext context, UserModel? user) {
    final isVerified = user?.isEmailVerified ?? false;
    return GestureDetector(
      onTap: isVerified ? null : () => _showEmailVerificationSheet(context),
      child: Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: isVerified
              ? null
              : Border.all(color: AppColors.warningLight, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
              decoration: BoxDecoration(
                color: isVerified
                    ? AppColors.successBg
                    : AppColors.warningBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isVerified ? Icons.mark_email_read : Icons.mail_outline,
                color: isVerified ? AppColors.successDark : AppColors.warningDark,
                size: ResponsiveHelper.iconSize(context, 22),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '이메일 인증',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!isVerified) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.warningDark,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            '미인증',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                  Text(
                    isVerified
                        ? '${user?.userEmail ?? ''} 인증 완료'
                        : '이메일 인증을 완료해주세요',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey500),
                  ),
                ],
              ),
            ),
            if (!isVerified)
              Icon(Icons.chevron_right,
                  color: AppColors.grey400,
                  size: ResponsiveHelper.iconSize(context, 20)),
          ],
        ),
      ),
    );
  }

  Future<void> _showEmailVerificationSheet(BuildContext context) async {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    if (user == null) return;

    int step = 0; // 0=코드발송, 1=코드입력, 2=완료
    bool isSending = false;
    bool isVerifying = false;
    final codeCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          Future<void> sendCode() async {
            if (user.userEmail == null || user.userEmail!.isEmpty) {
              ToastHelper.showError('등록된 이메일이 없습니다');
              return;
            }
            setModalState(() => isSending = true);
            try {
              final fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                  .httpsCallable('sendEmailVerificationCode');
              await fn.call({'email': user.userEmail});
              setModalState(() {
                isSending = false;
                step = 1;
              });
              ToastHelper.showSuccess(
                  '인증번호를 ${user.userEmail}로 발송했습니다');
            } on FirebaseFunctionsException catch (e) {
              setModalState(() => isSending = false);
              ToastHelper.showError(e.message ?? '발송 실패. 다시 시도해주세요');
            } catch (_) {
              setModalState(() => isSending = false);
              ToastHelper.showError('발송 실패. 다시 시도해주세요');
            }
          }

          Future<void> verifyCode() async {
            final code = codeCtrl.text.trim();
            if (code.length != 6) {
              ToastHelper.showWarning('6자리 인증번호를 입력해주세요');
              return;
            }
            setModalState(() => isVerifying = true);
            try {
              final fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                  .httpsCallable('verifyEmailCode');
              final result = await fn.call(
                  {'email': user.userEmail, 'code': code});
              final data = result.data as Map<String, dynamic>;

              if (data['valid'] == true) {
                // Firestore 업데이트
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .update({'isEmailVerified': true});
                // Provider 갱신
                await userProvider.refreshUserData();
                setModalState(() {
                  isVerifying = false;
                  step = 2;
                });
              } else {
                setModalState(() => isVerifying = false);
                final reason = data['reason'] as String? ?? '';
                final msg = switch (reason) {
                  'expired' => '인증번호가 만료되었습니다. 재발송해주세요',
                  'wrong_code' => '인증번호가 일치하지 않습니다',
                  'too_many_attempts' => '시도 횟수 초과. 재발송해주세요',
                  _ => '인증에 실패했습니다',
                };
                ToastHelper.showError(msg);
              }
            } catch (_) {
              setModalState(() => isVerifying = false);
              ToastHelper.showError('인증 확인 실패. 다시 시도해주세요');
            }
          }

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
              24,
              20,
              24,
              MediaQuery.of(ctx).viewInsets.bottom + 32,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.grey300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (step == 2) ...[
                  const Center(
                    child: Icon(Icons.check_circle,
                        color: AppColors.successMedium, size: 56),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      '이메일 인증 완료!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.successDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      '이제 이메일 알림을 받으실 수 있습니다.',
                      style: TextStyle(color: AppColors.grey500, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.successMedium,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('확인',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ] else ...[
                  Text(
                    step == 0 ? '이메일 인증' : '인증번호 입력',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    step == 0
                        ? '${user.userEmail ?? ''}로 인증번호를 발송합니다'
                        : '이메일로 받은 6자리 인증번호를 입력해주세요',
                    style:
                        TextStyle(color: AppColors.grey500, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  if (step == 1) ...[
                    TextField(
                      controller: codeCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofocus: true,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: '인증번호 6자리',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        counterText: '',
                        suffixIcon: isVerifying
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                              )
                            : null,
                      ),
                      onChanged: (v) {
                        if (v.length == 6 && !isVerifying) verifyCode();
                      },
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: isSending ? null : sendCode,
                      child: Text(
                        '인증번호 재발송',
                        style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (isSending || isVerifying)
                          ? null
                          : (step == 0 ? sendCode : verifyCode),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: (isSending || isVerifying)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              step == 0 ? '인증번호 받기' : '확인',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
    codeCtrl.dispose();
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
        color: Theme.of(context).colorScheme.surface,
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
        color: Theme.of(context).colorScheme.surface,
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
        color: Theme.of(context).colorScheme.surface,
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
                      activeThumbColor: theme.primaryColor,
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.error.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            final themeProvider = context.read<ThemeProvider>();
            final confirmed = await DialogHelper.showLogoutConfirm(context);

            if (confirmed) {
              themeProvider.reset();
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
                  color: AppColors.error,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Text(
                  '로그아웃',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: AppColors.error,
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
  // ━━━ 회원탈퇴 ━━━

  Widget _buildDeleteAccountButton(
      BuildContext context, UserProvider userProvider) {
    return TextButton(
      onPressed: () => _showDeleteAccountSheet(context, userProvider),
      child: Text(
        '회원탈퇴',
        style: TextStyle(
          color: AppColors.grey400,
          fontSize: 13,
          decoration: TextDecoration.underline,
          decorationColor: AppColors.grey400,
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountSheet(
      BuildContext context, UserProvider userProvider) async {
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    bool isLoading = false;
    String? errorMsg;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> doDelete() async {
            final pw = passwordCtrl.text.trim();
            if (pw.isEmpty) {
              setModal(() => errorMsg = '비밀번호를 입력해주세요');
              return;
            }
            setModal(() {
              isLoading = true;
              errorMsg = null;
            });

            final authService = AuthService();
            final err = await authService.deleteAccountWithPassword(pw);

            if (!ctx.mounted) return;

            if (err != null) {
              setModal(() {
                isLoading = false;
                errorMsg = err;
              });
            } else {
              Navigator.pop(ctx);
              context.read<ThemeProvider>().reset();
              await userProvider.signOut();
            }
          }

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
              24, 16, 24,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 핸들 바
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.grey300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 제목
                  const Text(
                    '회원탈퇴',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '탈퇴 후 계정 복구는 불가능합니다',
                    style: TextStyle(fontSize: 13, color: AppColors.grey500),
                  ),
                  const SizedBox(height: 16),

                  // 통합 안내 박스
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.errorLight),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '탈퇴 시 아래 사항을 확인해주세요',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.errorDeep,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final text in <String>[
                          '프로필 및 개인정보 즉시 삭제',
                          '업로드한 서류 삭제 (신분증, 통장사본 등)',
                          '진행 중인 지원·공고 자동 취소',
                          '탈퇴 후 30일간 재가입 제한',
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('• ',
                                    style: TextStyle(
                                        color: AppColors.errorDeep,
                                        fontSize: 12)),
                                Expanded(
                                  child: Text(text,
                                      style: const TextStyle(
                                          color: AppColors.errorDeep,
                                          fontSize: 12,
                                          height: 1.4)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 비밀번호 입력
                  const Text(
                    '비밀번호 확인',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      hintText: '현재 비밀번호 입력',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      errorText: errorMsg,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                        ),
                        onPressed: () => setModal(() => obscure = !obscure),
                      ),
                    ),
                    onSubmitted: (_) => doDelete(),
                  ),
                  const SizedBox(height: 20),

                  // 버튼
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isLoading ? null : () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isLoading ? null : doDelete,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  '탈퇴하기',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    passwordCtrl.dispose();
  }

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
      iconColor: AppColors.warningDark,
    );

    if (!confirmed || !context.mounted) return;

    DialogHelper.showLoading(context, message: '마이그레이션 진행 중...\n잠시만 기다려주세요.');

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
