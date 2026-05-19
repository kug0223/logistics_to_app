import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Providers
import '../../providers/user_provider.dart';
import '../../providers/theme_provider.dart';

// Utils
import '../../utils/dialog_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

// Services
import '../../services/firestore_service.dart';
import '../../services/monthly_review_service.dart';

// Screens
import '../common/settings_screen.dart';
import 'business_list_screen.dart';
import 'to_management/create_to_screen.dart';
import 'workforce_management/integrated_workforce_screen.dart';
import '../common/notification_screen.dart';
import '../../widgets/common/notification_badge.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import 'admin_review_list_screen.dart';
import '../../theme/app_colors.dart';

/// 공고 등록 전 필수 요건 체크 — 미충족 시 안내 다이얼로그 후 설정 화면으로 이동
/// 모든 요건을 충족하면 true 반환
/// 공고 등록 전 필수 요건 체크
/// 미충족 항목 표시 후 가장 우선순위 높은 목적지로 이동
/// 사업장 미등록 → BusinessListScreen / 이메일·사업자등록증 → SettingsScreen
Future<bool> _checkTORequirements(
  BuildContext context, {
  required bool hasApprovedBusiness,
  required bool isEmailVerified,
  required bool hasLicense,
}) async {
  final missing = <String>[];
  if (!hasApprovedBusiness) missing.add('사업장 등록');
  if (!isEmailVerified) missing.add('이메일 인증');
  if (!hasLicense) missing.add('사업자등록증 등록');
  if (missing.isEmpty) return true;

  // 사업장 미등록이 최우선 — BusinessListScreen으로, 나머지는 SettingsScreen으로
  final needsBusiness = !hasApprovedBusiness;
  final buttonText = needsBusiness ? '사업장 등록하러 가기' : '설정으로 이동';

  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StyledDialog(
      title: '공고 등록 불가',
      subtitle: '다음 항목을 먼저 완료해주세요',
      icon: Icons.block_outlined,
      headerColor: AppColors.error,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...missing.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: StyledDialogInfoCard.error(item),
            ),
          ),
          const SizedBox(height: 4),
          StyledDialogInfoCard.info(
            needsBusiness
                ? '사업장을 먼저 등록한 후 공고를 작성해주세요.'
                : '설정 화면에서 완료 후 다시 시도해주세요.',
          ),
        ],
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () => Navigator.pop(ctx, false),
        ),
        StyledDialogButton.primary(
          text: buttonText,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );

  if (proceed == true && context.mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => needsBusiness
            ? const BusinessListScreen()
            : const SettingsScreen(),
      ),
    );
  }
  return false;
}

/// 사업장 관리자 홈 화면 - 세련된 디자인
class BusinessAdminHomeScreen extends StatelessWidget {
  const BusinessAdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        final theme = Theme.of(context);
        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [theme.primaryColor, theme.colorScheme.secondary],
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 상단 헤더
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 24),
                      vertical: ResponsiveHelper.spacing(context, 20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 상단 바 (역할 + 로그아웃)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // ALfit 로고 + 역할
                            Row(
                              children: [
                                // ALfit 로고 + 점 (오른쪽 위)
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Text(
                                      'ALfit',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 1.3,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    Positioned(
                                      right: -ResponsiveHelper.spacing(context, 3),
                                      top: ResponsiveHelper.spacing(context, 5),
                                      child: Container(
                                        width: ResponsiveHelper.spacing(context, 4),
                                        height: ResponsiveHelper.spacing(context, 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.8),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                                // 역할 뱃지
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: ResponsiveHelper.spacing(context, 10),
                                    vertical: ResponsiveHelper.spacing(context, 5),
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.business,
                                        color: Colors.white,
                                        size: ResponsiveHelper.iconSize(context, 14),
                                      ),
                                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                      Text(
                                        '사업장',
                                        style: ResponsiveHelper.tinyStyle(
                                          context,
                                          color: Colors.white,
                                        ).copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            
                            // 🔔 알림 + 로그아웃 버튼
                            Row(
                              children: [
                                // 알림 버튼
                                NotificationBadge(
                                  child: Material(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const NotificationScreen(),
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                                        child: Icon(
                                          Icons.notifications_outlined,
                                          color: Colors.white,
                                          size: ResponsiveHelper.iconSize(context, 24),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                // 로그아웃 버튼
                                Material(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    onTap: () async {
                                      final confirmed = await DialogHelper.showLogoutConfirm(context);
                                      if (confirmed && context.mounted) {
                                        context.read<ThemeProvider>().reset();
                                        await userProvider.signOut();
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                                      child: Icon(
                                        Icons.logout,
                                        color: Colors.white,
                                        size: ResponsiveHelper.iconSize(context, 24),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        
                        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                        
                        // 인사말
                        Text(
                          '안녕하세요,',
                          style: ResponsiveHelper.bodyStyle(
                            context,
                            color: Colors.white.withValues(alpha: 0.95),
                          ),
                        ),
                        
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        
                        // 사용자 이름
                        Text(
                          '${userProvider.currentUser?.name ?? '관리자'}님',
                          style: ResponsiveHelper.titleStyle(context).copyWith(
                            color: Colors.white,
                            fontSize: ResponsiveHelper.titleStyle(context).fontSize! * 1.5,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                        
                        // 이메일
                        Text(
                          userProvider.currentUser?.userEmail ?? '',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  
                  // 메뉴 카드 영역
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.grey50,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
                        child: GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: ResponsiveHelper.spacing(context, 16),
                          mainAxisSpacing: ResponsiveHelper.spacing(context, 16),
                          children: [
                            // 1. 공고 등록
                            _buildMenuCard(
                              context,
                              icon: Icons.post_add,
                              title: '공고 등록',
                              subtitle: '새 공고 작성',
                              color: theme.primaryColor,
                              onTap: () async {
                                final user = userProvider.currentUser;
                                if (user == null) return;

                                // 승인된 사업장 보유 여부 확인
                                final businesses = await FirestoreService()
                                    .getMyBusiness(user.uid);
                                final hasApprovedBusiness =
                                    businesses.any((b) => b.isApproved);

                                if (!context.mounted) return;

                                final canProceed = await _checkTORequirements(
                                  context,
                                  hasApprovedBusiness: hasApprovedBusiness,
                                  isEmailVerified: user.isEmailVerified,
                                  hasLicense: user.businessLicenseImageUrl != null,
                                );
                                if (!canProceed || !context.mounted) return;

                                await NavigationHelper.push<bool>(
                                  context,
                                  destination: const AdminCreateTOScreen(),
                                  onReturn: (result) {
                                    if (result == true) {
                                      ToastHelper.showSuccess('공고가 등록되었습니다');
                                    }
                                  },
                                );
                              },
                            ),

                            // 2. 공고 관리
                            _buildMenuCard(
                              context,
                              icon: Icons.work_outline,
                              title: '공고 관리',
                              subtitle: '지원자 · 공고 현황',
                              color: theme.primaryColor,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const IntegratedWorkforceScreen(),
                                  ),
                                );
                              },
                            ),

                            // 3. 통계
                            _buildMenuCard(
                              context,
                              icon: Icons.bar_chart_outlined,
                              title: '통계',
                              subtitle: '공고 현황',
                              color: theme.primaryColor,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('통계 화면 준비 중입니다')),
                                );
                              },
                            ),
                            // 4. 리뷰 관리
                            FutureBuilder<int>(
                              future: () async {
                                final user = context.read<UserProvider>().currentUser;
                                if (user?.businessId == null) return 0;
                                final list = await MonthlyReviewService()
                                    .getPendingRequestsForBusiness(user!.businessId!);
                                return list.length;
                              }(),
                              builder: (context, snap) => _buildMenuCard(
                                context,
                                icon: Icons.rate_review_outlined,
                                title: '리뷰 관리',
                                subtitle: '평가 작성/조회',
                                color: theme.primaryColor,
                                badgeCount: snap.data,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const AdminReviewListScreen(),
                                    ),
                                  );
                                },
                              ),
                            ),

                            // 5. 설정
                            _buildMenuCard(
                              context,
                              icon: Icons.settings_outlined,
                              title: '설정',
                              subtitle: '앱 설정',
                              color: AppColors.grey600,
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
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 세련된 메뉴 카드 (단색 버전)
  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    final card = Card(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 아이콘
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: ResponsiveHelper.iconSize(context, 32),
                    color: color,
                  ),
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                
                // 제목
                Text(
                  title,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                
                // 부제목
                Text(
                  subtitle,
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.grey600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (badgeCount == null || badgeCount <= 0) return card;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
            child: Text(
              badgeCount > 99 ? '99+' : '$badgeCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
