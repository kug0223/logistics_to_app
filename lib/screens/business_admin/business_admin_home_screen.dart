import 'package:flutter/foundation.dart' show listEquals;
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
import '../../theme/app_colors.dart';
import '../../utils/business_picker_helper.dart';

/// 공고 등록 전 필수 요건 체크 — 미충족 시 안내 다이얼로그 후 설정 화면으로 이동
/// 모든 요건을 충족하면 true 반환
/// 공고 등록 전 필수 요건 체크
/// 미충족 항목 표시 후 가장 우선순위 높은 목적지로 이동
/// 사업장 미등록 → BusinessListScreen / 이메일·사업자등록증 → SettingsScreen

// [PERF-2026-07-16] Selector용 record — 7개 필드만 추출해 불필요한 rebuild 방지
typedef _AdminHomeData = ({
  bool isSubAdmin,
  String userName,
  String? effectiveBusinessId,
  bool canManageTo,
  bool canManageWorkers,
  bool canManageWage,
  bool canManageContract,
});

/// 사업장 관리자 홈 화면 - 세련된 디자인
class BusinessAdminHomeScreen extends StatefulWidget {
  const BusinessAdminHomeScreen({super.key});

  @override
  State<BusinessAdminHomeScreen> createState() => _BusinessAdminHomeScreenState();
}

class _BusinessAdminHomeScreenState extends State<BusinessAdminHomeScreen> {
  final _firestoreService = FirestoreService();
  bool? _hasApprovedBusiness; // null = 미조회, false = 미승인, true = 승인됨
  bool _isNavigating = false;
  // Firestore에 실제 존재하는 사업장 ID만 (managedBusinessIds 원시값 사용 금지 — 고아 문서 방어)
  List<String> _verifiedBusinessIds = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 승인된 사업장 유무 사전 조회 (메뉴 접근 가드용) — 투어 전 완료 필수
      await _loadApprovedBusinessStatus();
      if (!await TourHelper.isCompleted(TourHelper.adminHome)) {
        if (mounted) {
          await pushTourScreen(context, role: 'BUSINESS_ADMIN');
          if (mounted) await TourHelper.markCompleted(TourHelper.adminHome);
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
      // CF getMyBusiness 대신 UserProvider의 managedBusinessIds로 병렬 doc.get
      final managedIds = userProvider.currentUser?.managedBusinessIds ?? [];
      final businesses = await _firestoreService.getBusinessesByIds(managedIds);
      if (mounted) {
        setState(() {
          _hasApprovedBusiness = businesses.any((b) => b.isApproved);
          _verifiedBusinessIds = businesses.map((b) => b.id).toList();
        });
      }
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      // _hasApprovedBusiness를 null(미조회)로 유지 — false 설정 시 승인 사업장 없음으로 오인
    }
  }

  Future<void> _safeNavigate(Future<void> Function() action) async {
    if (_isNavigating) return;
    _isNavigating = true;  // setState 없이 — build()에서 미사용, push animation과 충돌 방지
    try {
      await action();
    } catch (e) {
      debugPrint('❌ 탐색 오류: $e');
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _requireApprovedBusiness(BuildContext context, Future<void> Function() proceed) async {
    if (_hasApprovedBusiness == null) {
      ToastHelper.showWarning('사업장 정보를 불러오는 중입니다. 잠시 후 다시 시도해주세요.');
      return;
    }
    if (_hasApprovedBusiness == false) {
      ToastHelper.showWarning('승인된 사업장이 있어야 이용할 수 있습니다.\n사업장 승인 후 다시 시도해주세요.');
      return;
    }
    await proceed();
  }

  @override
  Widget build(BuildContext context) {
    return Selector<UserProvider, _AdminHomeData>(
      selector: (_, p) => (
        isSubAdmin: p.isSubAdmin,
        userName: p.currentUser?.name ?? '관리자',
        effectiveBusinessId: p.effectiveBusinessId,
        canManageTo: p.can((perm) => perm.canManageTo),
        canManageWorkers: p.can((perm) => perm.canManageWorkers),
        canManageWage: p.can((perm) => perm.canManageWage),
        canManageContract: p.can((perm) => perm.canManageContract),
      ),
      builder: (context, data, _) {
        final theme = Theme.of(context);
        final isSubAdmin = data.isSubAdmin;
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
                                        fontSize: (ResponsiveHelper.titleStyle(context).fontSize ?? 18) * 1.3,
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
                                      onTap: () => context.read<UserProvider>().toggleAdminMode(),
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
                                      onTap: () => _safeNavigate(() async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const NotificationScreen(),
                                          ),
                                        );
                                      }),
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
                                    onTap: () => _safeNavigate(() async {
                                      final confirmed = await DialogHelper.showLogoutConfirm(context);
                                      if (confirmed && context.mounted) {
                                        context.read<ThemeProvider>().reset();
                                        await context.read<UserProvider>().signOut();
                                      }
                                    }),
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
                            '${data.userName}님',
                            style: ResponsiveHelper.titleStyle(context).copyWith(
                              color: Colors.white,
                              fontSize: (ResponsiveHelper.titleStyle(context).fontSize ?? 18) * 1.5,
                              fontWeight: FontWeight.bold,
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
                        // UX-03: bottom navigation bar 없음 (사업주 홈도 동일)
                        // 공고관리 → 급여관리 등 기능 간 이동 시 항상 홈으로 복귀 필요
                        // 사업주는 공고확인 → 출퇴근현황 → 급여확정 순 반복 패턴이 많아 불편도가 높음
                        child: GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: ResponsiveHelper.spacing(context, 16),
                          mainAxisSpacing: ResponsiveHelper.spacing(context, 16),
                          children: [
                            // 1. 공고 등록: BUSINESS_ADMIN 항상 / SUB_ADMIN은 canManageTo
                            if (!isSubAdmin || data.canManageTo)
                              _buildMenuCard(
                                context,
                                icon: Icons.post_add,
                                title: '공고 등록',
                                subtitle: '새 공고 작성',
                                color: theme.primaryColor,
                                onTap: () => _safeNavigate(() async {
                                  final user = context.read<UserProvider>().currentUser;
                                  if (user == null) return;

                                  if (!context.mounted) return;
                                  await NavigationHelper.push<bool>(
                                    context,
                                    destination: const AdminCreateTOScreen(),
                                    onReturn: (result) {
                                      if (result == true) {
                                        ToastHelper.showSuccess('공고가 등록되었습니다');
                                      }
                                    },
                                  );
                                }),
                              ),

                            // 2. 공고 관리: BUSINESS_ADMIN 항상 / SUB_ADMIN은 canManageTo OR canManageWorkers
                            if (!isSubAdmin || data.canManageTo || data.canManageWorkers)
                              _buildMenuCard(
                                context,
                                icon: Icons.work_outline,
                                title: '공고 관리',
                                subtitle: '지원자 · 공고 현황',
                                color: theme.primaryColor,
                                onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const IntegratedWorkforceScreen(),
                                    ),
                                  );
                                })),
                              ),

                            // 3. 급여 관리: 오늘 지급 배지 포함
                            if (!isSubAdmin || data.canManageWage)
                              _TodayPaymentBadgeCard(
                                businessIds: data.isSubAdmin
                                    ? (data.effectiveBusinessId != null
                                        ? [data.effectiveBusinessId!]
                                        : [])
                                    : _verifiedBusinessIds,
                                onTap: (reload) => _safeNavigate(() => _requireApprovedBusiness(context, () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const PayrollOverviewScreen(),
                                    ),
                                  );
                                  reload();
                                })),
                              ),

                            // 4. 계약서 관리: BUSINESS_ADMIN 항상 / SUB_ADMIN은 canManageContract
                            if (!isSubAdmin || data.canManageContract)
                              _buildMenuCard(
                                context,
                                icon: Icons.folder_outlined,
                                title: '계약서 관리',
                                subtitle: '계약서 현황·서명',
                                color: theme.primaryColor,
                                onTap: () => _safeNavigate(() => _requireApprovedBusiness(context, () async {
                                  if (!context.mounted) return;
                                  final biz = await BusinessPickerHelper.pick(context);
                                  if (biz == null || !context.mounted) return;
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AdminContractManagementScreen(
                                        businessId: biz.id,
                                      ),
                                    ),
                                  );
                                })),
                              ),

                            // 5. 통계: BUSINESS_ADMIN 항상 / SUB_ADMIN은 canManageWage
                            if (!isSubAdmin || data.canManageWage)
                              _buildMenuCard(
                                context,
                                icon: Icons.bar_chart_outlined,
                                title: '통계',
                                subtitle: '근태 · 급여 · 리뷰',
                                color: theme.primaryColor,
                                onTap: () => _safeNavigate(() async { await pushAdminStatsScreen(context); }),
                              ),

                            // 6. 설정: 항상 표시
                            _buildMenuCard(
                              context,
                              icon: Icons.settings_outlined,
                              title: '설정',
                              subtitle: '앱 설정',
                              color: AppColors.grey600,
                              onTap: () => _safeNavigate(() async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SettingsScreen(),
                                  ),
                                );
                                // C-02: 설정 화면에서 사업장 등록 후 돌아올 때 상태 갱신
                                if (mounted) _loadApprovedBusinessStatus();
                              }),
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
  final List<String> businessIds;
  // reload 콜백을 전달받아 호출자가 복귀 후 카운트 갱신 가능
  final void Function(VoidCallback reload) onTap;

  const _TodayPaymentBadgeCard({
    required this.businessIds,
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
    if (!listEquals(old.businessIds, widget.businessIds)) _loadCount();
  }

  Future<void> _loadCount() async {
    if (widget.businessIds.isEmpty) return;
    try {
      final counts = await Future.wait(
        widget.businessIds.map((id) => _payrollService.getTodayPaymentCount(businessId: id)),
      );
      final total = counts.fold<int>(0, (sum, n) => sum + (n ?? 0));
      if (mounted) setState(() => _count = total);
    } catch (e) {
      debugPrint('⚠️ 오늘 지급 건수 조회 실패: $e');
    }
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
      fit: StackFit.expand,
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
