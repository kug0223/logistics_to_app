import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../services/firestore_service.dart';
import '../../../controllers/workforce_controller.dart';
import 'workforce_list_view.dart';
import 'workforce_calendar_view.dart';
import '../../../widgets/common/gradient_scaffold.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../theme/app_colors.dart';
import '../../../services/fcm_service.dart';
import '../business_list_screen.dart';


/// ✨ 세련된 통합 인력 관리 화면 (business_home_screen 테마 적용)
class IntegratedWorkforceScreen extends StatefulWidget {
  /// 알림 딥링크 등에서 특정 사업장을 초기 선택할 때 전달. null이면 effectiveBusinessId 사용.
  final String? initialBusinessId;

  const IntegratedWorkforceScreen({super.key, this.initialBusinessId});

  @override
  State<IntegratedWorkforceScreen> createState() =>
      _IntegratedWorkforceScreenState();
}

class _IntegratedWorkforceScreenState extends State<IntegratedWorkforceScreen>
    with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();
  final WorkforceController _controller = WorkforceController();
  List<String> _allBusinessIds = [];
  String? _selectedBusinessId;
  bool _isCalendarView = false;
  bool _isLoading = false;

  late final VoidCallback _fcmRefreshCallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBusinessIds();
    _fcmRefreshCallback = () { if (mounted) _controller.reload(context); };
    FCMService().addAdminRefreshListener(_fcmRefreshCallback);
  }

  @override
  void dispose() {
    FCMService().removeAdminRefreshListener(_fcmRefreshCallback);
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Cloud Functions이 갱신한 Firestore 상태를 반영
      if (mounted) _controller.reload(context);
    }
  }

  /// 관리자의 모든 사업장 ID 로드
  Future<void> _loadBusinessIds() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final userProvider = context.read<UserProvider>();
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showWarning('로그인 정보를 찾을 수 없습니다.');
        return;
      }

      // SubAdmin인 경우 effectiveBusinessId로 직접 사용 (adminIds에 없으므로 getMyBusiness 결과 0건)
      final effectiveBizId = userProvider.effectiveBusinessId;
      if (userProvider.isSubAdmin && effectiveBizId != null) {
        setState(() {
          _allBusinessIds = [effectiveBizId];
          _selectedBusinessId = effectiveBizId;
        });
        if (mounted) _controller.load(context);
        return;
      }

      final businesses = await _firestoreService.getMyBusiness(uid);

      if (!mounted) return;

      if (businesses.isEmpty) {
        ToastHelper.showWarning('등록된 사업장이 없습니다.');
        return;
      }

      setState(() {
        _allBusinessIds = businesses.map((b) => b.id).toList();
        // initialBusinessId(알림 딥링크) 우선 → 목록 첫 번째
        final preferred = widget.initialBusinessId;
        _selectedBusinessId = (preferred != null && _allBusinessIds.contains(preferred))
            ? preferred
            : _allBusinessIds.first;
      });

      if (mounted) _controller.load(context);
      debugPrint('✅ 관리 사업장: ${_allBusinessIds.length}개');
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedBusinessId == null) {
      // 빈 상태(사업장 미등록)에도 메인 화면과 동일한 '공고 관리' 타이틀 유지
      return GradientScaffold(
        title: '공고 관리',
        body: AppEmptyState(
          icon: Icons.business_center,
          title: '등록된 사업장이 없습니다',
          subtitle: '사업장을 먼저 등록해주세요',
          action: FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BusinessListScreen()),
            ),
            icon: const Icon(Icons.add_business, size: 18),
            label: const Text('사업장 등록'),
          ),
        ),
      );
    }

    return GradientScaffold(
      title: '공고 관리',
      onRefresh: _loadBusinessIds,
      body: ChangeNotifierProvider.value(
        value: _controller,
        child: Column(
          children: [
            _buildViewToggleBar(),
            Expanded(
              child: _isCalendarView
                  ? const WorkforceCalendarView()
                  : const WorkforceListView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewToggleBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 10),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 6),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 3)),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildViewToggleButton(
                  icon: Icons.view_list,
                  label: '목록',
                  isSelected: !_isCalendarView,
                  onTap: () => setState(() => _isCalendarView = false),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                _buildViewToggleButton(
                  icon: Icons.calendar_month,
                  label: '캘린더',
                  isSelected: _isCalendarView,
                  onTap: () => setState(() => _isCalendarView = true),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (!_isCalendarView)
            Consumer<WorkforceController>(
              builder: (ctx, controller, _) => _buildFilterButton(ctx, controller),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterButton(BuildContext ctx, WorkforceController controller) {
    final theme = Theme.of(ctx);
    final hasFilters = controller.hasActiveFilters;

    return Material(
      color: hasFilters
          ? theme.primaryColor.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: controller.requestShowFilter,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(ctx, 12),
            vertical: ResponsiveHelper.spacing(ctx, 6),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.filter_list,
                color: hasFilters ? theme.primaryColor : AppColors.grey600,
                size: ResponsiveHelper.iconSize(ctx, 24),
              ),
              if (hasFilters)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(ctx, 4)),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.primaryColor,
                          theme.primaryColor.withValues(alpha: 0.8),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: theme.primaryColor.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    constraints: BoxConstraints(
                      minWidth: ResponsiveHelper.spacing(ctx, 18),
                      minHeight: ResponsiveHelper.spacing(ctx, 18),
                    ),
                    child: Center(
                      child: Text(
                        '${controller.activeFilterCount}',
                        style: ResponsiveHelper.tinyStyle(
                          ctx,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewToggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      // 두 버튼이 항상 같은 최소 너비 유지 — "캘린더"(더 긴 텍스트) 기준
      constraints: BoxConstraints(minWidth: ResponsiveHelper.spacing(context, 76)),
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 6),
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 15),
              color: isSelected ? theme.primaryColor : AppColors.grey500,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 5)),
            Text(
              label,
              style: ResponsiveHelper.smallStyle(
                context,
                color: isSelected ? theme.primaryColor : AppColors.grey500,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}