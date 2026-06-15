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


/// ✨ 세련된 통합 인력 관리 화면 (business_home_screen 테마 적용)
class IntegratedWorkforceScreen extends StatefulWidget {
  const IntegratedWorkforceScreen({super.key});

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
        _selectedBusinessId = _allBusinessIds.first;
      });

      if (mounted) _controller.load(context);
      debugPrint('✅ 관리 사업장: ${_allBusinessIds.length}개');
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedBusinessId == null) {
      return GradientScaffold(
        title: '인력 관리',
        body: AppEmptyState(
          icon: Icons.business_center,
          title: '등록된 사업장이 없습니다',
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
        ],
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
    return InkWell(
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
          mainAxisSize: MainAxisSize.min,
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
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}