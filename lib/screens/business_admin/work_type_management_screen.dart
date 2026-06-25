import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/business_work_type_model.dart';
import '../../services/firestore_service.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/pickers/add_work_type_sheet.dart';
import '../../widgets/work_type_icon.dart';
import '../../utils/toast_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import 'work_type_detail_screen.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/app_menu_sheet.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../models/core/to_model.dart';

/// 업무 유형 관리 화면 — businessId/businessName을 외부에서 주입받음
class WorkTypeManagementScreen extends StatefulWidget {
  final String businessId;
  final String businessName;

  const WorkTypeManagementScreen({
    super.key,
    required this.businessId,
    required this.businessName,
  });

  @override
  State<WorkTypeManagementScreen> createState() => _WorkTypeManagementScreenState();
}

class _WorkTypeManagementScreenState extends State<WorkTypeManagementScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  List<BusinessWorkTypeModel> _workTypes = [];
  bool _isLoading = true;
  bool _isReordering = false;

  @override
  void initState() {
    super.initState();
    _loadWorkTypes();
  }

  Future<void> _loadWorkTypes() async {
    setState(() => _isLoading = true);
    try {
      final workTypes =
          await _firestoreService.getBusinessWorkTypes(widget.businessId);
      if (!mounted) return;
      setState(() {
        _workTypes = workTypes;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 업무 유형 로드 실패: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ToastHelper.showError('업무 유형을 불러올 수 없습니다');
    }
  }

  /// 업무 유형 추가
  Future<void> _showAddDialog() async {
    final result = await AddWorkTypeSheet.show(context);
    if (result == null || !mounted) return;

    final newId = await _firestoreService.addBusinessWorkType(
      businessId: widget.businessId,
      name: result['name'] as String,
      icon: (result['icon'] as String?) ?? '',
      color: result['iconColor'] as String? ?? '#FFFFFF',
      backgroundColor: result['backgroundColor'] as String?,
    );

    if (newId != null && mounted) {
      await _loadWorkTypes();
      if (!mounted) return;

      final newWorkType = _workTypes.firstWhere(
        (wt) => wt.id == newId,
        orElse: () => BusinessWorkTypeModel(
          id: newId,
          businessId: widget.businessId,
          name: result['name'] as String,
          icon: (result['icon'] as String?) ?? '',
          color: result['iconColor'] as String? ?? '#FFFFFF',
          backgroundColor: result['backgroundColor'] as String?,
          displayOrder: _workTypes.length,
          createdAt: DateTime.now(),
        ),
      );

      if (!mounted) return;
      final goToDetail = await showDialog<bool>(
        context: context,
        builder: (ctx) => StyledDialog(
          title: '등록 완료!',
          subtitle: '업무유형이 성공적으로 등록되었습니다',
          icon: Icons.check_circle,
          headerColor: AppColors.success,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StyledDialogInfoCard.info(
                '상세 정보(설명, 이미지 등)를 추가하면 지원자에게 더 많은 정보를 제공할 수 있어요!',
              ),
            ],
          ),
          actions: [
            StyledDialogButton.cancel(
              text: '나중에',
              onPressed: () => Navigator.pop(ctx, false),
            ),
            StyledDialogButton.primary(
              text: '상세 정보 입력',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );

      if (goToDetail == true && mounted) {
        _openDetailScreen(newWorkType, initialEditMode: true);
      }
    }
  }

  /// 업무 유형 수정
  Future<void> _showEditDialog(BusinessWorkTypeModel workType) async {
    final result = await AddWorkTypeSheet.show(
      context,
      editTarget: workType,
    );
    if (result == null || !mounted) return;

    final success = await _firestoreService.updateBusinessWorkType(
      businessId: widget.businessId,
      workTypeId: workType.id,
      name: result['name'] as String,
      icon: result['icon'] as String?,
      color: result['iconColor'] as String? ?? '#FFFFFF',
      backgroundColor: result['backgroundColor'] as String?,
    );
    if (!mounted) return;

    if (success) _loadWorkTypes();
  }

  /// 삭제 확인 다이얼로그
  Future<void> _confirmDelete(BusinessWorkTypeModel workType) async {
    final activeTOSnap = await FirebaseFirestore.instance
        .collection('tos')
        .where('businessId', isEqualTo: widget.businessId)
        .where('status',
            whereIn: [TOStatus.active, TOStatus.full, TOStatus.scheduled])
        .get();

    final affectedCount = activeTOSnap.docs.where((doc) {
      final details = doc.data()['workDetails'] as List<dynamic>? ?? [];
      return details.any(
          (d) => (d as Map<String, dynamic>)['workType'] == workType.name);
    }).length;

    if (!mounted) return;

    if (affectedCount > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('활성 공고 있음'),
          content: Text(
            '이 업무 유형을 사용하는 활성 공고가 $affectedCount개 있습니다.\n'
            '삭제하면 해당 공고의 업무 유형 표시에 영향을 줄 수 있습니다.\n계속하시겠습니까?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('계속'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: AppDialogSize.insetV,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 헤더
                  Container(
                    padding: ResponsiveHelper.cardPadding(context),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.error,
                          AppColors.error.withValues(alpha: 0.8),
                        ],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: ResponsiveHelper.spacing(context, 48),
                          height: ResponsiveHelper.spacing(context, 48),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.business,
                              color: Colors.white70,
                              size: ResponsiveHelper.iconSize(context, 24)),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                        Expanded(
                          child: Text(
                            '업무 유형 삭제',
                            style: ResponsiveHelper.titleStyle(context).copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 컨텐츠
                  Padding(
                    padding: ResponsiveHelper.cardPadding(context),
                    child: Column(
                      children: [
                        Icon(
                          Icons.delete_forever,
                          size: ResponsiveHelper.iconSize(context, 64),
                          color: AppColors.error.withValues(alpha: 0.5),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                        Text(
                          '정말로 삭제하시겠습니까?',
                          style: ResponsiveHelper.subtitleStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        Text(
                          workType.name,
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        Text(
                          '삭제된 데이터는 복구할 수 없습니다',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 버튼
                  Padding(
                    padding: ResponsiveHelper.cardPadding(context),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.spacing(context, 16),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('취소'),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.error,
                                  AppColors.error.withValues(alpha: 0.8),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.error.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => Navigator.pop(context, true),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: ResponsiveHelper.spacing(context, 16),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.delete,
                                        color: Colors.white,
                                        size: ResponsiveHelper.iconSize(context, 20),
                                      ),
                                      SizedBox(
                                          width: ResponsiveHelper.spacing(context, 8)),
                                      Text(
                                        '삭제',
                                        style:
                                            ResponsiveHelper.bodyStyle(context).copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      final success = await _firestoreService.deleteBusinessWorkType(
        businessId: widget.businessId,
        workTypeId: workType.id,
      );
      if (!mounted) return;
      if (success) {
        _loadWorkTypes();
      } else {
        ToastHelper.showError('삭제에 실패했습니다');
      }
    }
  }

  Future<void> _swapWorkTypeOrder(
      BusinessWorkTypeModel a, BusinessWorkTypeModel b) async {
    if (_isReordering) return;
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.update(
        db
            .collection('businesses')
            .doc(widget.businessId)
            .collection('workTypes')
            .doc(a.id),
        {'displayOrder': b.displayOrder});
    batch.update(
        db
            .collection('businesses')
            .doc(widget.businessId)
            .collection('workTypes')
            .doc(b.id),
        {'displayOrder': a.displayOrder});
    setState(() => _isReordering = true);
    try {
      await batch.commit();
      if (!mounted) return;
      ToastHelper.showSuccess('순서가 변경되었습니다');
      _loadWorkTypes();
    } catch (e) {
      if (mounted) ToastHelper.showError('순서 변경에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isReordering = false);
    }
  }

  Future<void> _moveUp(int index) async {
    if (index == 0) return;
    await _swapWorkTypeOrder(_workTypes[index], _workTypes[index - 1]);
  }

  Future<void> _moveDown(int index) async {
    if (index >= _workTypes.length - 1) return;
    await _swapWorkTypeOrder(_workTypes[index], _workTypes[index + 1]);
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '업무 유형 관리',
      onRefresh: _loadWorkTypes,
      body: _isLoading
          ? const LoadingWidget(message: '업무 유형을 불러오는 중...')
          : _workTypes.isEmpty
              ? _buildEmptyState()
              : _buildWorkTypeList(),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return AppEmptyState(
      icon: Icons.work_outline,
      title: '등록된 업무 유형이 없습니다',
      subtitle: '업무 유형을 추가하고 공고를 관리해보세요',
      action: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _showAddDialog,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 20),
              ),
              decoration: BoxDecoration(
                border: Border.all(
                  color: theme.primaryColor.withValues(alpha: 0.3),
                  width: 2,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    color: theme.primaryColor,
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Text(
                    '업무 유형 추가',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWorkTypeList() {
    final theme = Theme.of(context);

    return ListView(
      padding: ResponsiveHelper.listPadding(context),
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: List.generate(_workTypes.length, (index) {
                final workType = _workTypes[index];
                final isFirst = index == 0;
                final isLast = index == _workTypes.length - 1;
                final iconColor = FormatHelper.parseColor(
                    workType.backgroundColor ?? '#2196F3');

                return Column(
                  children: [
                    InkWell(
                      onTap: () => _openDetailScreen(workType),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 16),
                          vertical: ResponsiveHelper.spacing(context, 12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: ResponsiveHelper.iconSize(context, 46),
                              height: ResponsiveHelper.iconSize(context, 46),
                              decoration: BoxDecoration(
                                color: iconColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: WorkTypeIcon.build(
                                  workType,
                                  size: ResponsiveHelper.iconSize(context, 24),
                                ),
                              ),
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 14)),
                            Expanded(
                              child: Text(
                                workType.name,
                                style: ResponsiveHelper.bodyStyle(context)
                                    .copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.more_vert,
                                  color: AppColors.grey400,
                                  size: ResponsiveHelper.iconSize(context, 20)),
                              onPressed: () => _showWorkTypeMenuSheet(
                                  context, theme, workType, index, isFirst, isLast),
                              tooltip: '더보기',
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!isLast)
                      Divider(
                        height: 1,
                        indent: ResponsiveHelper.spacing(context, 76),
                        endIndent: 0,
                        color: AppColors.grey100,
                      ),
                  ],
                );
              }),
            ),
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        _buildListAddButton(),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
      ],
    );
  }

  Widget _buildListAddButton() {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showAddDialog,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 20),
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.primaryColor.withValues(alpha: 0.3),
              width: 2,
              style: BorderStyle.solid,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 24)),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(
                '새 업무 유형 추가',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWorkTypeMenuSheet(
    BuildContext context,
    ThemeData theme,
    BusinessWorkTypeModel workType,
    int index,
    bool isFirst,
    bool isLast,
  ) {
    AppMenuSheet.show(
      context: context,
      itemGroups: [
        [
          if (!isFirst)
            AppMenuSheetItem(
              icon: Icons.arrow_upward,
              label: '위로 이동',
              color: theme.primaryColor,
              onTap: () =>
                  _handleMenuAction('moveUp', workType, index, isFirst, isLast),
            ),
          if (!isLast)
            AppMenuSheetItem(
              icon: Icons.arrow_downward,
              label: '아래로 이동',
              color: theme.primaryColor,
              onTap: () =>
                  _handleMenuAction('moveDown', workType, index, isFirst, isLast),
            ),
        ],
        [
          AppMenuSheetItem(
            icon: Icons.info_outline,
            label: '상세 정보',
            color: AppColors.info,
            onTap: () =>
                _handleMenuAction('detail', workType, index, isFirst, isLast),
          ),
          AppMenuSheetItem(
            icon: Icons.edit,
            label: '아이콘수정',
            color: AppColors.warning,
            onTap: () =>
                _handleMenuAction('edit', workType, index, isFirst, isLast),
          ),
        ],
        [
          AppMenuSheetItem(
            icon: Icons.delete,
            label: '삭제',
            color: AppColors.error,
            isDanger: true,
            onTap: () =>
                _handleMenuAction('delete', workType, index, isFirst, isLast),
          ),
        ],
      ],
    );
  }

  void _handleMenuAction(
    String action,
    BusinessWorkTypeModel workType,
    int index,
    bool isFirst,
    bool isLast,
  ) {
    switch (action) {
      case 'moveUp':
        if (!isFirst) _moveUp(index);
        break;
      case 'moveDown':
        if (!isLast) _moveDown(index);
        break;
      case 'detail':
        _openDetailScreen(workType);
        break;
      case 'edit':
        _showEditDialog(workType);
        break;
      case 'delete':
        _confirmDelete(workType);
        break;
    }
  }

  Future<void> _openDetailScreen(BusinessWorkTypeModel workType,
      {bool initialEditMode = false}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkTypeDetailScreen(
          workType: workType,
          initialEditMode: initialEditMode,
        ),
      ),
    );

    if (result == true && mounted) {
      _loadWorkTypes();
    }
  }
}
