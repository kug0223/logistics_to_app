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
import '../../utils/tour_helper.dart';
import '../common/tour_screen.dart';

// Services
import '../../services/firestore_service.dart';

// Screens
import '../common/settings_screen.dart';
import 'to_management/create_to_screen.dart';
import 'workforce_management/integrated_workforce_screen.dart';
import '../common/notification_screen.dart';
import '../../widgets/common/notification_badge.dart';
import 'admin_stats_screen.dart';
import 'admin_contract_management_screen.dart';
import 'payroll/payroll_overview_screen.dart';
import '../../services/payroll_payment_service.dart';
import 'to_prerequisites_helper.dart';
import '../../theme/app_colors.dart';

/// 공고 등록 전 필수 요건 체크 — 미충족 시 안내 다이얼로그 후 설정 화면으로 이동
/// 모든 요건을 충족하면 true 반환
/// 공고 등록 전 필수 요건 체크
/// 미충족 항목 표시 후 가장 우선순위 높은 목적지로 이동
/// 사업장 미등록 → BusinessListScreen / 이메일·사업자등록증 → SettingsScreen

/// 사업장 관리자 홈 화면 - 세련된 디자인
class BusinessAdminHomeScreen extends StatefulWidget {
  const BusinessAdminHomeScreen({super.key});

  @override
  State<BusinessAdminHomeScreen> createState() => _BusinessAdminHomeScreenState();
}

class _BusinessAdminHomeScreenState extends State<BusinessAdminHomeScreen> {
  final _firestoreService = FirestoreService();
  bool? _hasApprovedBusiness; // null = 미조회, false = 미승인, true = 승인됨

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 승인된 사업장 유무 사전 조회 (메뉴 접근 가드용)
      _loadApprovedBusinessStatus();
      if (!await TourHelper.isCompleted(TourHelper.adminHome)) {
        if (mounted) {
          await pushTourScreen(context, role: 'BUSINESS_ADMIN');
          await TourHelper.markCompleted(TourHelper.adminHome);
        }
      }
    });
  }

  Future<void> _loadApprovedBusinessStatus() async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return;
    try {
      // SubAdmin은 adminIds에 없으므로 getMyBusiness 결과 0건 → effectiveBusinessId로 직접 조회
      final effectiveBizId = userProvider.effectiveBusinessId;
      if (userProvider.isSubAdmin && effectiveBizId != null) {
        final biz = await _firestoreService.getBusinessById(effectiveBizId);
        if (mounted) setState(() => _hasApprovedBusiness = biz?.isApproved ?? false);
        return;
      }
      final businesses = await _firestoreService.getMyBusiness(uid);
      if (mounted) setState(() => _hasApprovedBusiness = businesses.any((b) => b.isApproved));
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      if (mounted) setState(() => _hasApprovedBusiness = false);
    }
  }

  void _requireApprovedBusiness(BuildContext context, VoidCallback proceed) {
    if (_hasApprovedBusiness == null) {
      ToastHelper.showWarning('사업장 정보를 불러오는 중입니다. 잠시 후 다시 시도해주세요.');
      return;
    }
    if (_hasApprovedBusiness == false) {
      ToastHelper.showWarning('승인된 사업장이 있어야 이용할 수 있습니다.\n사업장 승인 후 다시 시도해주세요.');
      return;
    }
    proceed();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        final theme = Theme.of(context);
        final isSubAdmin = userProvider.isSubAdmin;
        final isLandscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
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
                  // 상단 헤더 — 가로 모드에서 vertical 패딩 축소
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 24),
                      vertical: ResponsiveHelper.spacing(
                          context, isLandscape ? 8 : 20),
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
                                      style: ResponsiveHelper.titleStyle(context).copyWith(
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
                                        isSubAdmin ? '하위 관리자' : '관리자',
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
                                // 하위 관리자: 근무자 모드 전환 버튼
                                if (isSubAdmin) ...[
                                  Material(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      onTap: () => userProvider.toggleAdminMode(),
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: ResponsiveHelper.spacing(context, 10),
                                          vertical: ResponsiveHelper.spacing(context, 8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.person_outline,
                                              color: Colors.white,
                                              size: ResponsiveHelper.iconSize(context, 16),
                                            ),
                                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                            Text(
                                              '근무자 모드',
                                              style: ResponsiveHelper.tinyStyle(
                                                context,
                                                color: Colors.white,
                                              ).copyWith(fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                ],
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
                        
                        // 가로 모드에서 인사말 섹션 숨김 (공간 절약)
                        if (!isLandscape) ...[
                          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                          Text(
                            '안녕하세요,',
                            style: ResponsiveHelper.bodyStyle(
                              context,
                              color: Colors.white.withValues(alpha: 0.95),
                            ),
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
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
                            // 1. 공고 등록: BUSINESS_ADMIN 항상 / SUB_ADMIN은 canManageTo
                            if (!isSubAdmin || userProvider.can((p) => p.canManageTo))
                              _buildMenuCard(
                                context,
                                icon: Icons.post_add,
                                title: '공고 등록',
                                subtitle: '새 공고 작성',
                                color: theme.primaryColor,
                                onTap: () async {
                                  final user = userProvider.currentUser;
                                  if (user == null) return;

                                  if (!isSubAdmin) {
                                    final businesses = await _firestoreService
                                        .getMyBusiness(user.uid);
                                    final hasApprovedBusiness =
                                        businesses.any((b) => b.isApproved);
                                    if (!context.mounted) return;
                                    final canProceed = await checkTOPrerequisites(
                                      context,
                                      hasApprovedBusiness: hasApprovedBusiness,
                                      isEmailVerified: user.isEmailVerified,
                                      hasLicense: user.businessLicenseImageUrl != null,
                                    );
                                    if (!canProceed || !context.mounted) return;
                                  }

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

                            // 2. 공고 관리: BUSINESS_ADMIN 항상 / SUB_ADMIN은 canManageTo OR canManageWorkers
                            if (!isSubAdmin ||
                                userProvider.can((p) => p.canManageTo) ||
                                userProvider.can((p) => p.canManageWorkers))
                              _buildMenuCard(
                                context,
                                icon: Icons.work_outline,
                                title: '공고 관리',
                                subtitle: '지원자 · 공고 현황',
                                color: theme.primaryColor,
                                onTap: () => _requireApprovedBusiness(context, () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const IntegratedWorkforceScreen(),
                                    ),
                                  );
                                }),
                              ),

                            // 3. 급여 관리: 오늘 지급 배지 포함
                            if (!isSubAdmin || userProvider.can((p) => p.canManageWage))
                              _TodayPaymentBadgeCard(
                                businessId: userProvider.effectiveBusinessId,
                                onTap: (reload) async {
                                  _requireApprovedBusiness(context, () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const PayrollOverviewScreen(),
                                      ),
                                    );
                                    reload();
                                  });
                                },
                              ),

                            // 4. 계약서 관리: BUSINESS_ADMIN 항상 / SUB_ADMIN은 canManageContract
                            if (!isSubAdmin || userProvider.can((p) => p.canManageContract))
                              _buildMenuCard(
                                context,
                                icon: Icons.folder_outlined,
                                title: '계약서 관리',
                                subtitle: '계약서 현황·서명',
                                color: theme.primaryColor,
                                onTap: () => _requireApprovedBusiness(context, () async {
                                  var bizId = userProvider.effectiveBusinessId;
                                  if (bizId == null) {
                                    final uid = userProvider.currentUser?.uid;
                                    if (uid != null) {
                                      final businesses = await _firestoreService.getMyBusiness(uid);
                                      bizId = businesses.isNotEmpty ? businesses.first.id : null;
                                    }
                                  }
                                  if (bizId == null) {
                                    ToastHelper.showWarning('사업장 정보를 먼저 등록해주세요');
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AdminContractManagementScreen(
                                        businessId: bizId!,
                                      ),
                                    ),
                                  );
                                }),  // _requireApprovedBusiness 닫힘
                              ),

                            // 5. 통계: BUSINESS_ADMIN 항상 / SUB_ADMIN은 canManageWage
                            if (!isSubAdmin || userProvider.can((p) => p.canManageWage))
                              _buildMenuCard(
                                context,
                                icon: Icons.bar_chart_outlined,
                                title: '통계',
                                subtitle: '근태 · 급여 · 리뷰',
                                color: theme.primaryColor,
                                onTap: () => pushAdminStatsScreen(context),
                              ),

                            // 6. 설정: 항상 표시
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
  }) {
    return Card(
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
  }
}

// ── 오늘 지급 배지가 있는 급여 관리 카드 ────────────────────────────────

class _TodayPaymentBadgeCard extends StatefulWidget {
  final String? businessId;
  // reload 콜백을 전달받아 호출자가 복귀 후 카운트 갱신 가능
  final void Function(VoidCallback reload) onTap;

  const _TodayPaymentBadgeCard({
    required this.businessId,
    required this.onTap,
  });

  @override
  State<_TodayPaymentBadgeCard> createState() => _TodayPaymentBadgeCardState();
}

class _TodayPaymentBadgeCardState extends State<_TodayPaymentBadgeCard> {
  int _count = 0;
  final _payrollService = PayrollPaymentService();

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  @override
  void didUpdateWidget(_TodayPaymentBadgeCard old) {
    super.didUpdateWidget(old);
    if (old.businessId != widget.businessId) _loadCount();
  }

  Future<void> _loadCount() async {
    if (widget.businessId == null) return;
    final count = await _payrollService.getTodayPaymentCount(
      businessId: widget.businessId!,
    );
    if (mounted) setState(() => _count = count);
  }

  @override
  Widget build(BuildContext context) {
    final card = Card(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () => widget.onTap(_loadCount),
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
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    size: ResponsiveHelper.iconSize(context, 32),
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                Text(
                  '급여 관리',
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '월별 급여·지급 현황',
                  style: ResponsiveHelper.smallStyle(
                      context, color: AppColors.grey600),
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

    if (_count <= 0) return card;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: -4,
          right: -4,
          child: Semantics(
            label: '오늘 지급 예정 ${_count > 99 ? '99건 이상' : '$_count건'}',
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
              child: ExcludeSemantics(
                child: Text(
                  _count > 99 ? '99+' : '$_count',
                  style: ResponsiveHelper.tinyStyle(context, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
