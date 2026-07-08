import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
import '../../utils/test_data_helper.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../models/core/to_model.dart';
import '../../models/core/business_model.dart';
import '../../utils/business_picker_helper.dart';

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
  bool _isNavigating = false;
  // Firestore에 실제 존재하는 사업장 ID만 (managedBusinessIds 원시값 사용 금지 — 고아 문서 방어)
  List<String> _verifiedBusinessIds = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 승인된 사업장 유무 사전 조회 (메뉴 접근 가드용)
      _loadApprovedBusinessStatus();
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
      final businesses = await _firestoreService.getMyBusiness(uid);
      if (mounted) {
        setState(() {
          _hasApprovedBusiness = businesses.any((b) => b.isApproved);
          _verifiedBusinessIds = businesses.map((b) => b.id).toList();
        });
      }
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      if (mounted) setState(() => _hasApprovedBusiness = false);
    }
  }

  Future<void> _safeNavigate(Future<void> Function() action) async {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    try {
      await action();
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
                                // 더미 데이터 (디버그 전용)
                                if (kDebugMode) ...[
                                  Material(
                                    color: Colors.white.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      onTap: _showDummyDataDialog,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                                        child: Icon(
                                          Icons.science,
                                          color: Colors.white,
                                          size: ResponsiveHelper.iconSize(context, 24),
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
                            if (!isSubAdmin || userProvider.can((p) => p.canManageTo))
                              _buildMenuCard(
                                context,
                                icon: Icons.post_add,
                                title: '공고 등록',
                                subtitle: '새 공고 작성',
                                color: theme.primaryColor,
                                onTap: () => _safeNavigate(() async {
                                  final user = userProvider.currentUser;
                                  if (user == null) return;

                                  if (!isSubAdmin) {
                                    final businesses = await _firestoreService
                                        .getMyBusiness(user.uid);
                                    final approvedList =
                                        businesses.where((b) => b.isApproved).toList();
                                    final hasApprovedBusiness = approvedList.isNotEmpty;
                                    // C-03: 전체 승인 사업장 병렬 체크 — .first 단독 참조 금지
                                    BusinessModel? firstApprovedBiz;
                                    bool hasWorkTypes = false;
                                    if (approvedList.isNotEmpty) {
                                      final results = await Future.wait(
                                        approvedList.map((biz) => _firestoreService
                                            .getBusinessWorkTypes(biz.id)),
                                      );
                                      final idx = results.indexWhere((wt) => wt.isNotEmpty);
                                      if (idx >= 0) {
                                        hasWorkTypes = true;
                                        firstApprovedBiz = approvedList[idx];
                                      } else {
                                        firstApprovedBiz = approvedList.first;
                                      }
                                    }
                                    if (!context.mounted) return;
                                    final canProceed = await checkTOPrerequisites(
                                      context,
                                      hasApprovedBusiness: hasApprovedBusiness,
                                      hasWorkTypes: hasWorkTypes,
                                      hasSeal: user.sealBase64 != null &&
                                          user.sealBase64!.isNotEmpty,
                                      hasLicense: user.businessLicenseImageUrl != null,
                                      approvedBusiness: firstApprovedBiz,
                                    );
                                    if (!canProceed || !context.mounted) return;

                                    // 진행중 공고 수 사전 체크 — 폼 진입 자체를 차단
                                    final limit = await _firestoreService.getMaxActiveTOLimit();
                                    if (!context.mounted) return;
                                    final activeCount = await _firestoreService.countAllActiveTO(user.uid);
                                    if (activeCount >= limit) {
                                      if (!context.mounted) return;
                                      ToastHelper.showError('진행 중인 공고가 $limit개를 초과할 수 없습니다.\n기존 공고를 마감한 후 등록해주세요.');
                                      return;
                                    }
                                  }

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
                            if (!isSubAdmin ||
                                userProvider.can((p) => p.canManageTo) ||
                                userProvider.can((p) => p.canManageWorkers))
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
                            if (!isSubAdmin || userProvider.can((p) => p.canManageWage))
                              _TodayPaymentBadgeCard(
                                businessIds: userProvider.isSubAdmin
                                    ? (userProvider.effectiveBusinessId != null
                                        ? [userProvider.effectiveBusinessId!]
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
                            if (!isSubAdmin || userProvider.can((p) => p.canManageContract))
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
                            if (!isSubAdmin || userProvider.can((p) => p.canManageWage))
                              _buildMenuCard(
                                context,
                                icon: Icons.bar_chart_outlined,
                                title: '통계',
                                subtitle: '근태 · 급여 · 리뷰',
                                color: theme.primaryColor,
                                onTap: () => _safeNavigate(() async { pushAdminStatsScreen(context); }),
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

  Future<void> _showDummyDataDialog() async {
    final biz = await BusinessPickerHelper.pick(context);
    if (biz == null || !mounted) return;
    final businessId = biz.id;

    showDialog(
      context: context,
      builder: (ctx) => StyledDialog(
        title: '테스트 데이터 관리',
        icon: Icons.science,
        headerColor: AppColors.warning,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.group_add, color: AppColors.info),
              title: const Text('지원자 생성'),
              subtitle: const Text('공고 선택 → 인원 수 조정 → 생성'),
              onTap: () async {
                Navigator.pop(ctx);
                await _createDummyApplicationsFlow(businessId);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.access_time, color: AppColors.success),
              title: const Text('출근 데이터 생성'),
              subtitle: const Text('날짜 선택 → 확정자 70% 출근 처리'),
              onTap: () async {
                Navigator.pop(ctx);
                await _createDummyAttendanceFlow(businessId);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.schedule, color: AppColors.info),
              title: const Text('시나리오별 출퇴근 생성'),
              subtitle: const Text('정시·지각·조퇴·연장 등 8가지 상황 랜덤 배정'),
              onTap: () async {
                Navigator.pop(ctx);
                await _createDummyAttendanceScenariosFlow(businessId);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.star_outline, color: AppColors.warning),
              title: const Text('리뷰 데이터 생성'),
              subtitle: const Text('모든 더미 근무자에게 평점 생성'),
              onTap: () async {
                Navigator.pop(ctx);
                await _createDummyReviewsFlow(businessId);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: AppColors.error),
              title: const Text('더미 데이터 전체 삭제',
                  style: TextStyle(color: AppColors.error)),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await DialogHelper.showDangerConfirm(
                  context,
                  title: '더미 데이터 삭제',
                  message: '모든 더미 데이터(지원자·지원서·출근·리뷰)를 삭제합니다.',
                  confirmText: '삭제',
                );
                if (ok && mounted) {
                  await TestDataHelper.clearAllDummyData();
                  if (mounted) ToastHelper.showSuccess('더미 데이터 삭제 완료');
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  /// 더미 지원서 생성 흐름 — 공고 선택 → (단기) 슬롯 선택 → 생성
  Future<void> _createDummyApplicationsFlow(String businessId) async {
    try {
    final snap = await FirebaseFirestore.instance
        .collection('tos')
        .where('businessId', isEqualTo: businessId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get(const GetOptions(source: Source.server));

    if (snap.docs.isEmpty) {
      if (mounted) ToastHelper.showWarning('등록된 공고가 없습니다. 먼저 공고를 생성하세요.');
      return;
    }

    // 활성·비활성 포함 전체 공고 표시 — 상태를 라벨에 표기
    final toDocs = snap.docs.map((d) {
      final data = d.data();
      final title = data['title'] as String? ?? d.id;
      final type = data['type'] as String? ?? TOType.flex;
      final status = data['status'] as String? ?? TOStatus.active;
      final typeLabel = type == TOType.contract ? '[장기]' : '[단기]';
      final bizName = data['businessName'] as String? ?? '';
      final bizSuffix = bizName.isNotEmpty ? ' ($bizName)' : '';
      final isActive = status == TOStatus.active;
      final statusSuffix = isActive ? '' : ' [$status]';
      return (id: d.id, label: '$typeLabel $title$bizSuffix$statusSuffix',
              type: type, isActive: isActive);
    }).toList();

    if (!mounted) return;

    // 2단계: 공고 선택 바텀시트 — 비활성(예약/마감) 공고는 회색+비활성
    final selectedTo = await showModalBottomSheet<({String id, String type})>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('공고 선택',
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: AppColors.grey100),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: toDocs.map((to) {
                    final color = to.isActive
                        ? Theme.of(context).primaryColor
                        : AppColors.grey400;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: to.isActive
                            ? () => Navigator.pop(sheetCtx, (id: to.id, type: to.type))
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.assignment_outlined,
                                    size: 20, color: color),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(to.label,
                                  style: ResponsiveHelper.bodyStyle(context,
                                      color: to.isActive
                                          ? AppColors.grey800
                                          : AppColors.grey400),
                                ),
                              ),
                              Icon(
                                to.isActive
                                    ? Icons.chevron_right
                                    : Icons.lock_outline,
                                color: AppColors.grey300,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (selectedTo == null || !mounted) return;

    String? selectedSlotId;
    DateTime? selectedSlotDate;

    // 3단계: 단기 TO인 경우 슬롯(날짜) 선택
    if (selectedTo.type == TOType.flex) {
      // orderBy 없이 쿼리 (복합 인덱스 불필요) → 클라이언트 정렬
      // 모집중(open)인 슬롯만 — full(만석)/closed(마감) 제외
      // TO 자체가 ACTIVE인 경우에만 여기 도달하므로(공고 선택 시 비활성 제외) 추가 TO 상태 체크 불필요
      final slotsSnap = await FirebaseFirestore.instance
          .collection('tos')
          .doc(selectedTo.id)
          .collection('slots')
          .where('status', isEqualTo: 'open')
          .limit(30)
          .get();

      if (!mounted) return;

      if (slotsSnap.docs.isEmpty) {
        ToastHelper.showWarning('이 공고에 등록된 날짜(슬롯)가 없습니다.');
        return;
      }

      // 날짜 오름차순 정렬 (클라이언트)
      final sortedDocs = slotsSnap.docs.toList()
        ..sort((a, b) {
          final aTs = a.data()['date'] as Timestamp?;
          final bTs = b.data()['date'] as Timestamp?;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          return aTs.compareTo(bTs);
        });

      // visibleFrom 미래인 슬롯 제외 — status='open'이어도 예약공개 슬롯은 선택 불가
      final now = DateTime.now();
      final activeDocs = sortedDocs.where((d) {
        final vf = (d.data()['visibleFrom'] as Timestamp?)?.toDate().toLocal();
        return vf == null || !vf.isAfter(now);
      }).toList();

      if (activeDocs.isEmpty) {
        ToastHelper.showWarning('모집중인 날짜(슬롯)가 없습니다.');
        return;
      }

      // 슬롯 목록 구성 — 날짜 + 현재 확정/대기 인원 표시
      final slotOptions = activeDocs.map((d) {
        final data = d.data();
        final date = (data['date'] as Timestamp).toDate().toLocal();
        final confirmed = (data['confirmedCount'] as num?)?.toInt() ?? 0;
        final pending = (data['pendingCount'] as num?)?.toInt() ?? 0;
        final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
        final wd = weekdays[date.weekday - 1];
        final label =
            '${date.month}/${date.day}($wd)  확정 $confirmed명 · 대기 $pending명';
        return (id: d.id, label: label, date: date);
      }).toList();

      final selected =
          await showModalBottomSheet<({String id, DateTime date})>(
        context: context,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (sheetCtx) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('날짜 선택',
                      style: ResponsiveHelper.subtitleStyle(context)
                          .copyWith(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: AppColors.grey100),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: slotOptions.map((s) {
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(
                              sheetCtx, (id: s.id, date: s.date)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.info.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.calendar_today,
                                      size: 18, color: AppColors.info),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(s.label,
                                    style: ResponsiveHelper.bodyStyle(context,
                                        color: AppColors.grey800)),
                                ),
                                Icon(Icons.chevron_right,
                                    color: AppColors.grey300, size: 20),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );

      if (selected == null || !mounted) return;
      selectedSlotId = selected.id;
      selectedSlotDate = selected.date;
    }

    // 4단계: 인원 수 조정 바텀시트
    if (!mounted) return;
    final counts = await showModalBottomSheet<({int pending, int confirmed})>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        int pending = 2;
        int confirmed = 3;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Widget counter(
              String label,
              String sub,
              Color color,
              int value,
              VoidCallback onMinus,
              VoidCallback onPlus,
            ) {
              return Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.person_outline, size: 20, color: color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                          style: ResponsiveHelper.bodyStyle(ctx,
                              color: AppColors.grey800)
                              .copyWith(fontWeight: FontWeight.w600)),
                        Text(sub,
                          style: ResponsiveHelper.smallStyle(ctx,
                              color: AppColors.grey500)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.remove_circle_outline, color: value > 0 ? color : AppColors.grey300),
                    onPressed: value > 0 ? onMinus : null,
                  ),
                  SizedBox(
                    width: 32,
                    child: Text('$value',
                      textAlign: TextAlign.center,
                      style: ResponsiveHelper.subtitleStyle(ctx)
                          .copyWith(fontWeight: FontWeight.bold, color: color)),
                  ),
                  IconButton(
                    icon: Icon(Icons.add_circle_outline, color: value < 20 ? color : AppColors.grey300),
                    onPressed: value < 20 ? onPlus : null,
                  ),
                ],
              );
            }

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
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
                      Text('인원 수 설정',
                        style: ResponsiveHelper.subtitleStyle(ctx)
                            .copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('최대 20명 · 현재 총 ${pending + confirmed}명',
                        style: ResponsiveHelper.smallStyle(ctx,
                            color: AppColors.grey500)),
                      const SizedBox(height: 20),
                      Divider(height: 1, color: AppColors.grey100),
                      const SizedBox(height: 16),
                      counter(
                        '대기', 'PENDING',
                        AppColors.warning,
                        pending,
                        () => setSheetState(() => pending--),
                        () => setSheetState(() => pending++),
                      ),
                      const SizedBox(height: 12),
                      counter(
                        '확정', 'CONFIRMED',
                        AppColors.success,
                        confirmed,
                        () => setSheetState(() => confirmed--),
                        () => setSheetState(() => confirmed++),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (pending + confirmed) > 0
                              ? () => Navigator.pop(sheetCtx,
                                  (pending: pending, confirmed: confirmed))
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.info,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            '대기 $pending명 + 확정 $confirmed명 생성',
                            style: ResponsiveHelper.bodyStyle(ctx,
                                    color: Colors.white)
                                .copyWith(fontWeight: FontWeight.bold),
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
      },
    );

    if (counts == null || !mounted) return;

    // 5단계: 더미 지원서 생성
    await TestDataHelper.createDummyApplications(
      toId: selectedTo.id,
      pendingCount: counts.pending,
      confirmedCount: counts.confirmed,
      slotId: selectedSlotId,
      slotDate: selectedSlotDate,
    );

    if (mounted) {
      ToastHelper.showSuccess(
        '더미 지원자 ${counts.pending + counts.confirmed}명 생성 완료 (대기 ${counts.pending} + 확정 ${counts.confirmed})',
      );
    }
    } catch (e) {
      if (mounted) ToastHelper.showError('더미 지원자 생성 실패: $e');
    }
  }

  /// 더미 출근 데이터 생성 흐름 — 날짜 선택 후 생성
  Future<void> _createDummyAttendanceFlow(String businessId) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
      helpText: '출근 데이터 생성 날짜',
      confirmText: '생성',
      cancelText: '취소',
    );
    if (date == null || !mounted) return;

    try {
      await TestDataHelper.createDummyAttendance(
          businessId: businessId, date: date);
      if (mounted) ToastHelper.showSuccess('더미 출근 데이터 생성 완료');
    } catch (e) {
      if (mounted) ToastHelper.showError('출근 데이터 생성 실패: 확정된 더미 지원자가 없을 수 있습니다.');
    }
  }

  /// 시나리오별 출퇴근 데이터 생성 흐름 — 날짜 선택 후 8가지 상황 랜덤 배정
  Future<void> _createDummyAttendanceScenariosFlow(String businessId) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
      helpText: '시나리오 출퇴근 날짜 선택',
      confirmText: '생성',
      cancelText: '취소',
    );
    if (date == null || !mounted) return;

    try {
      await TestDataHelper.createDummyAttendanceScenarios(
          businessId: businessId, date: date);
      if (mounted) ToastHelper.showSuccess('시나리오별 출퇴근 데이터 생성 완료');
    } catch (e) {
      if (mounted) ToastHelper.showError('생성 실패: 확정된 더미 지원자가 없을 수 있습니다.');
    }
  }

  /// 더미 리뷰 데이터 생성 흐름
  Future<void> _createDummyReviewsFlow(String businessId) async {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    if (user == null || !mounted) return;

    try {
      // 사업장 이름 조회
      String bizName = businessId;
      final businesses = await _firestoreService.getMyBusiness(user.uid);
      if (!mounted) return;
      final matched = businesses.where((b) => b.id == businessId).toList();
      if (matched.isNotEmpty) bizName = matched.first.name;

      await TestDataHelper.createDummyReviews(
        businessId: businessId,
        businessName: bizName,
        reviewerId: user.uid,
        reviewerName: user.name,
      );
      if (mounted) ToastHelper.showSuccess('더미 리뷰 생성 완료');
    } catch (e) {
      if (mounted) ToastHelper.showError('리뷰 생성 실패: 더미 지원자를 먼저 생성해주세요.');
    }
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
    if (old.businessIds != widget.businessIds) _loadCount();
  }

  Future<void> _loadCount() async {
    if (widget.businessIds.isEmpty) return;
    int total = 0;
    for (final id in widget.businessIds) {
      total += await _payrollService.getTodayPaymentCount(businessId: id);
    }
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
