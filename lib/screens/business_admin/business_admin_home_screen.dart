import 'dart:async' show unawaited;

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
import '../../utils/attendance_list_pdf.dart';

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

// [PERF-2026-07-16] Selector용 record — 필요한 필드만 추출해 불필요한 rebuild 방지
typedef _AdminHomeData = ({
  String userName,
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
    AttendanceListPdf.preloadFonts();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // M2: 사업장 조회(Firestore)와 투어 완료 확인(SharedPreferences)은 독립적 — 병렬 실행
      final results = await Future.wait([
        _loadApprovedBusinessStatus(),
        TourHelper.isCompleted(TourHelper.adminHome),
      ]);
      final tourDone = results[1] as bool;
      if (!tourDone && mounted) {
        await pushTourScreen(context, role: 'BUSINESS_ADMIN');
        if (mounted) await TourHelper.markCompleted(TourHelper.adminHome);
      }
    });
  }

  Future<void> _loadApprovedBusinessStatus() async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return;
    try {
      // CF getMyBusiness 대신 UserProvider의 managedBusinessIds로 병렬 doc.get
      final managedIds = userProvider.currentUser?.managedBusinessIds ?? [];
      final businesses = await _firestoreService.getBusinessesByIds(managedIds);
      if (mounted) {
        final ids = businesses.map((b) => b.id).toList();
        setState(() {
          _hasApprovedBusiness = businesses.any((b) => b.isApproved);
          _verifiedBusinessIds = ids;
        });
        // 배지 위젯이 마운트되기 전에 CF 컨테이너를 미리 깨워둔다.
        // 결과는 사용하지 않으며, 오류도 무시한다.
        if (ids.isNotEmpty) {
          final id = ids.first;
          unawaited(
            Future.wait([
              _firestoreService.getUnsentApplicationsByBusiness(id),
              PayrollPaymentService().getTotalNotTransferredCount(businessId: id),
            ]).catchError((_) => []),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      // _hasApprovedBusiness를 null(미조회)로 유지 — false 설정 시 승인 사업장 없음으로 오인
      if (mounted) ToastHelper.showError('사업장 정보를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.');
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
      _isNavigating = false; // M1: build()에서 미사용 — setState 불필요, 불필요한 rebuild 방지
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
        userName: p.currentUser?.name ?? '관리자',
      ),
      builder: (context, data, _) {
        final theme = Theme.of(context);
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
                                        '관리자',
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${data.userName}님',
                                  style: ResponsiveHelper.titleStyle(context).copyWith(
                                    color: Colors.white,
                                    fontSize: (ResponsiveHelper.titleStyle(context).fontSize ?? 18) * 1.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                                ],
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
                        // 지원자 홈의 미서명 계약 바 콘텐츠 높이(42dp)만큼 하단 공간 확보 → 카드 크기 일관성
                        // (body의 SafeArea가 이미 nav bar inset 처리 → viewPadding.bottom 추가 불필요)
                        padding: EdgeInsets.fromLTRB(
                          ResponsiveHelper.spacing(context, 20),
                          ResponsiveHelper.spacing(context, 20),
                          ResponsiveHelper.spacing(context, 20),
                          ResponsiveHelper.spacing(context, 20) + ResponsiveHelper.spacing(context, 42),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const crossAxisCount = 2;
                            const rowCount = 3;
                            final spacing = ResponsiveHelper.spacing(context, 16);
                            final cardWidth = (constraints.maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
                            final cardHeight = (constraints.maxHeight - spacing * (rowCount - 1)) / rowCount;
                            final aspectRatio = (cardWidth / cardHeight).clamp(0.75, double.infinity);
                            return GridView.count(
                              crossAxisCount: crossAxisCount,
                              crossAxisSpacing: spacing,
                              mainAxisSpacing: spacing,
                              childAspectRatio: aspectRatio,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                            // 1. 공고 등록
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

                            // 2. 공고 관리
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
                            _TodayPaymentBadgeCard(
                              businessIds: _verifiedBusinessIds,
                              onTap: (reload) => _safeNavigate(() => _requireApprovedBusiness(context, () async {
                                final up = context.read<UserProvider>();
                                if (!up.can((p) => p.canManageWage)) {
                                  ToastHelper.showWarning('급여 관리 권한이 없습니다.');
                                  return;
                                }
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PayrollOverviewScreen(),
                                  ),
                                );
                                reload();
                              })),
                            ),

                            // 4. 계약서 관리: 미발송 배지 포함
                            _UnsentContractBadgeCard(
                              businessIds: _verifiedBusinessIds,
                              onTap: (reload) => _safeNavigate(() => _requireApprovedBusiness(context, () async {
                                if (!context.mounted) return;
                                // [PERM-C1] canManageContract 세부 권한 체크
                                final up = context.read<UserProvider>();
                                if (!up.can((p) => p.canManageContract)) {
                                  ToastHelper.showWarning('계약서 관리 권한이 없습니다.');
                                  return;
                                }
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
                                reload();
                              })),
                            ),

                            // 5. 통계
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
                            );
                          },
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

// ── 계약서 미발송 배지가 있는 계약서 관리 카드 ──────────────────────────

class _UnsentContractBadgeCard extends StatefulWidget {
  final List<String> businessIds;
  final void Function(VoidCallback reload) onTap;

  const _UnsentContractBadgeCard({
    required this.businessIds,
    required this.onTap,
  });

  @override
  State<_UnsentContractBadgeCard> createState() => _UnsentContractBadgeCardState();
}

class _UnsentContractBadgeCardState extends State<_UnsentContractBadgeCard> {
  int _count = 0;
  final _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCount();
    });
  }

  @override
  void didUpdateWidget(_UnsentContractBadgeCard old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.businessIds, widget.businessIds)) _loadCount();
  }

  Future<void> _loadCount() async {
    if (widget.businessIds.isEmpty) return;
    if (!context.read<UserProvider>().can((p) => p.canManageContract)) return;
    final counts = await Future.wait(
      widget.businessIds.map((bizId) async {
        try {
          final apps = await _firestoreService.getUnsentApplicationsByBusiness(bizId);
          return apps.length;
        } catch (e) {
          debugPrint('⚠️ 계약서 미발송 배지 조회 실패 ($bizId): $e');
          return 0;
        }
      }),
    );
    final total = counts.fold<int>(0, (acc, n) => acc + n);
    if (mounted) setState(() => _count = total);
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
                    Icons.folder_outlined,
                    size: ResponsiveHelper.iconSize(context, 32),
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                Text(
                  '계약서 관리',
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '계약서 현황·서명',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
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
          top: 10,
          right: 10,
          child: Semantics(
            label: '계약서 미발송 ${_count > 99 ? '99명 이상' : '$_count명'}',
            child: Container(
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: ExcludeSemantics(
                child: Text(
                  _count > 99 ? '99+' : '$_count',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ],
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCount();
    });
  }

  @override
  void didUpdateWidget(_TodayPaymentBadgeCard old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.businessIds, widget.businessIds)) _loadCount();
  }

  Future<void> _loadCount() async {
    if (widget.businessIds.isEmpty) return;
    // [PERM-B1] canManageWage 없는 서브어드민은 미이체 배지 조회 생략
    if (!context.read<UserProvider>().can((p) => p.canManageWage)) return;
    try {
      final counts = await Future.wait(
        widget.businessIds.map((id) => _payrollService.getTotalNotTransferredCount(businessId: id)),
      );
      final total = counts.fold<int>(0, (acc, n) => acc + (n ?? 0));
      if (mounted) setState(() => _count = total);
    } catch (e) {
      debugPrint('⚠️ 미이체 배지 조회 실패: $e');
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
          top: 10,
          right: 10,
          child: Semantics(
            label: '미이체 ${_count > 99 ? '99명 이상' : '$_count명'}',
            child: Container(
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: ExcludeSemantics(
                child: Text(
                  _count > 99 ? '99+' : '$_count',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
