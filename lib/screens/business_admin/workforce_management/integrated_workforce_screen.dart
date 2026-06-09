import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_colors.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../services/firestore_service.dart';
import '../../../controllers/workforce_controller.dart';
import 'workforce_list_view.dart';
import 'workforce_calendar_view.dart';
import '../../../utils/test_data_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../widgets/common/gradient_scaffold.dart';
import '../../../widgets/common/app_empty_state.dart';


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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBusinessIds();
  }

  @override
  void dispose() {
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
        title: '공고 관리',
        body: AppEmptyState(
          icon: Icons.business_center,
          title: '등록된 사업장이 없습니다',
        ),
      );
    }

    return GradientScaffold(
      title: '공고 관리',
      actions: [
        // 더미 데이터 (디버그 전용)
        if (kDebugMode)
          IconButton(
            icon: Icon(Icons.science,
                size: ResponsiveHelper.iconSize(context, 24),
                color: Colors.white),
            onPressed: _showDummyDataDialog,
            tooltip: '테스트 데이터',
          ),
        // 목록/캘린더 토글
        Container(
          margin: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            _buildToggleButton(
              icon: Icons.view_list, label: '목록',
              isSelected: !_isCalendarView,
              onTap: () => setState(() => _isCalendarView = false),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            _buildToggleButton(
              icon: Icons.calendar_month, label: '캘린더',
              isSelected: _isCalendarView,
              onTap: () => setState(() => _isCalendarView = true),
            ),
          ]),
        ),
      ],
      body: ChangeNotifierProvider.value(
        value: _controller,
        child: _isCalendarView
            ? const WorkforceCalendarView()
            : const WorkforceListView(),
      ),
    );
  }

  /// ✨ 토글 버튼 (탭바 스타일 - 명확하게 보임)
  Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 18),
              color: isSelected ? Theme.of(context).primaryColor : Colors.white,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              label,
              style: ResponsiveHelper.smallStyle(context).copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected ? Theme.of(context).primaryColor : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 더미 데이터 다이얼로그 (디버그 전용) ─────────────────────────

  Future<void> _showDummyDataDialog() async {
    if (_selectedBusinessId == null) {
      ToastHelper.showError('사업장이 선택되지 않았습니다.');
      return;
    }

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
              leading: const Icon(Icons.group_add),
              title: const Text('TO에 지원자 추가'),
              subtitle: const Text('공고 선택 → 확정/대기 인원 생성'),
              onTap: () async {
                Navigator.pop(ctx);
                await _createDummyApplicationsFlow();
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
                  message: '모든 더미 데이터를 삭제합니다.',
                  confirmText: '삭제',
                );
                if (ok && mounted) {
                  await TestDataHelper.clearAllDummyData();
                  if (mounted) {
                    ToastHelper.showSuccess('더미 데이터 삭제 완료');
                    _controller.reload(context);
                  }
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

  Future<void> _createDummyApplicationsFlow() async {
    // TO 목록 조회
    final snap = await FirebaseFirestore.instance
        .collection('tos')
        .where('businessId', isEqualTo: _selectedBusinessId)
        .where('status', whereIn: ['active', 'full'])
        .limit(50)
        .get();

    if (snap.docs.isEmpty) {
      ToastHelper.showWarning('등록된 공고가 없습니다. 먼저 공고를 생성하세요.');
      return;
    }

    final options = snap.docs
        .map((d) => MapEntry(d.id, d.data()['title'] as String? ?? d.id))
        .toList();

    if (!mounted) return;

    final selectedId = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: options
            .map((e) => ListTile(
                  title: Text(e.value),
                  onTap: () => Navigator.pop(context, e.key),
                ))
            .toList(),
      ),
    );

    if (selectedId == null || !mounted) return;

    await TestDataHelper.createDummyApplications(
      toId: selectedId,
      pendingCount: 2,
      confirmedCount: 3,
    );

    if (mounted) {
      ToastHelper.showSuccess('더미 지원자 생성 완료');
      _controller.reload(context);
    }
  }

}