import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/core/business_work_type_model.dart';
import '../../models/core/business_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/pickers/add_work_type_sheet.dart';
import '../../widgets/work_type_icon.dart';
import '../../utils/toast_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import 'work_type_detail_screen.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../theme/app_colors.dart';
import '../../utils/image_helper.dart';
import '../../widgets/common/app_menu_sheet.dart';
import '../../widgets/app_select_field.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../models/core/to_model.dart';

/// ✨ 세련된 업무 유형 관리 화면
class WorkTypeManagementScreen extends StatefulWidget {
  const WorkTypeManagementScreen({super.key});

  @override
  State<WorkTypeManagementScreen> createState() => _WorkTypeManagementScreenState();
}

class _WorkTypeManagementScreenState extends State<WorkTypeManagementScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<BusinessModel> _myBusinesses = [];
  BusinessModel? _selectedBusiness;
  
  List<BusinessWorkTypeModel> _workTypes = [];
  bool _isLoading = true;
  bool _isLoadingBusinesses = true;

  @override
  void initState() {
    super.initState();
    _loadMyBusinesses();
  }

  Future<void> _loadMyBusinesses() async {
    setState(() => _isLoadingBusinesses = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        if (mounted) setState(() => _isLoadingBusinesses = false);
        return;
      }

      // SubAdmin은 adminIds에 없으므로 effectiveBusinessId로 직접 조회
      final effectiveBizId = userProvider.effectiveBusinessId;
      if (userProvider.isSubAdmin && effectiveBizId != null) {
        final biz = await _firestoreService.getBusinessById(effectiveBizId);
        if (!mounted) return;
        setState(() {
          _myBusinesses = biz != null ? [biz] : [];
          if (_myBusinesses.isNotEmpty) {
            _selectedBusiness = _myBusinesses.first;
            _loadWorkTypes();
          } else {
            _isLoading = false;
          }
          _isLoadingBusinesses = false;
        });
        return;
      }

      final businesses = await _firestoreService.getMyBusiness(uid);

      if (!mounted) return;
      setState(() {
        _myBusinesses = businesses;
        if (_myBusinesses.isNotEmpty) {
          _selectedBusiness = _myBusinesses.first;
          _loadWorkTypes();
        } else {
          _isLoading = false;
        }
        _isLoadingBusinesses = false;
      });

      if (businesses.isEmpty) {
        ToastHelper.showInfo('등록된 사업장이 없습니다');
      }
    } catch (e) {
      debugPrint('❌ 사업장 목록 로드 실패: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingBusinesses = false;
        _isLoading = false;
      });
      ToastHelper.showError('사업장 목록을 불러올 수 없습니다');
    }
  }

  Future<void> _loadWorkTypes() async {
    if (_selectedBusiness == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final workTypes = await _firestoreService.getBusinessWorkTypes(_selectedBusiness!.id);
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

  /// 업무 유형 추가 — 새 바텀시트 사용
  Future<void> _showAddDialog() async {
    if (_selectedBusiness == null) {
      ToastHelper.showWarning('사업장을 먼저 선택해주세요');
      return;
    }

    final result = await AddWorkTypeSheet.show(context);
    if (result == null || !mounted) return;

    final newId = await _firestoreService.addBusinessWorkType(
      businessId: _selectedBusiness!.id,
      name: result['name'] as String,
      icon: (result['icon'] as String?) ?? '',
      color: result['iconColor'] as String? ?? '#FFFFFF',
      backgroundColor: result['backgroundColor'] as String?,
    );

    if (newId != null && mounted) {
      await _loadWorkTypes();
      if (!mounted) return; // _loadWorkTypes await 후 재확인

      // 상세 정보 바로 입력 여부
      final newWorkType = _workTypes.firstWhere(
        (wt) => wt.id == newId,
        orElse: () => BusinessWorkTypeModel(
          id: newId,
          businessId: _selectedBusiness!.id,
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

  /// 업무 유형 수정 — 새 바텀시트 사용
  Future<void> _showEditDialog(BusinessWorkTypeModel workType) async {
    if (_selectedBusiness == null) return;

    final result = await AddWorkTypeSheet.show(
      context,
      editTarget: workType,
    );
    if (result == null || !mounted) return;

    final success = await _firestoreService.updateBusinessWorkType(
      businessId: _selectedBusiness!.id,
      workTypeId: workType.id,
      name: result['name'] as String,
      icon: result['icon'] as String?,
      color: result['iconColor'] as String? ?? '#FFFFFF',
      backgroundColor: result['backgroundColor'] as String?,
    );
    if (!mounted) return;

    if (success) _loadWorkTypes();
  }

  /// ✨ 세련된 삭제 확인 다이얼로그
  Future<void> _confirmDelete(BusinessWorkTypeModel workType) async {
    if (_selectedBusiness == null) return;

    // [P-01] whereIn 30개 제한 분석:
    // whereIn 대상이 status 값 3개(active/full/scheduled)로 고정 — 제한 미해당.
    // 업무유형 ID가 아닌 status를 기준으로 조회 후 workType 이름 매칭은 in-memory 처리.
    // 향후 업무유형 수가 늘어도 이 쿼리 구조상 whereIn 제한 이슈 발생하지 않음.
    final activeTOSnap = await FirebaseFirestore.instance
        .collection('tos')
        .where('businessId', isEqualTo: _selectedBusiness!.id)
        .where('status', whereIn: [TOStatus.active, TOStatus.full, TOStatus.scheduled])
        .get();

    // [특이사항] workType 이름 기준 매칭 — 이름 변경 이력이 있으면 affectedCount가 실제보다 적게 표시될 수 있음
    // TO 생성 이후 workType 이름이 변경된 경우 해당 TO는 이 검사에서 누락됨
    final affectedCount = activeTOSnap.docs.where((doc) {
      final details = doc.data()['workDetails'] as List<dynamic>? ?? [];
      return details.any((d) => (d as Map<String, dynamic>)['workType'] == workType.name);
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
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
              maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                // ✨ 헤더
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
                      SizedBox(
                        width: ResponsiveHelper.spacing(context, 48),
                        height: ResponsiveHelper.spacing(context, 48),
                        child: _selectedBusiness?.mainImageUrl != null
                            ? ImageHelper.buildCachedImage(
                                _selectedBusiness!.mainImageUrl!,
                                width: ResponsiveHelper.spacing(context, 48),
                                height: ResponsiveHelper.spacing(context, 48),
                                fit: BoxFit.cover,
                                borderRadius: BorderRadius.circular(12),
                                memCacheWidth: 96,
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(Icons.business, color: Theme.of(context).primaryColor, size: ResponsiveHelper.iconSize(context, 24)),
                              ),
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
                // ✨ 컨텐츠
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
                // ✨ 버튼
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
                          child: Text('취소'),
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
                                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                    Text(
                                      '삭제',
                                      style: ResponsiveHelper.bodyStyle(context).copyWith(
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
        businessId: _selectedBusiness!.id,
        workTypeId: workType.id,
      );

      if (success && mounted) {
        _loadWorkTypes();
      }
    }
  }

  Future<void> _swapWorkTypeOrder(
      BusinessWorkTypeModel a, BusinessWorkTypeModel b) async {
    final bizId = _selectedBusiness!.id;
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.update(
        db.collection('businesses').doc(bizId).collection('workTypes').doc(a.id),
        {'displayOrder': b.displayOrder});
    batch.update(
        db.collection('businesses').doc(bizId).collection('workTypes').doc(b.id),
        {'displayOrder': a.displayOrder});
    try {
      await batch.commit();
      if (!mounted) return;
      ToastHelper.showSuccess('순서가 변경되었습니다');
      _loadWorkTypes();
    } catch (e) {
      if (mounted) ToastHelper.showError('순서 변경에 실패했습니다');
    }
  }

  /// 순서 위로 이동
  Future<void> _moveUp(int index) async {
    if (index == 0 || _selectedBusiness == null) return;
    await _swapWorkTypeOrder(_workTypes[index], _workTypes[index - 1]);
  }

  /// 순서 아래로 이동
  Future<void> _moveDown(int index) async {
    if (index >= _workTypes.length - 1 || _selectedBusiness == null) return;
    await _swapWorkTypeOrder(_workTypes[index], _workTypes[index + 1]);
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '업무 유형 관리',
      onRefresh: _loadWorkTypes,
      actions: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Colors.white),
          onPressed: _selectedBusiness != null ? _showAddDialog : null,
          tooltip: '업무 유형 추가',
        ),
      ],
      body: _isLoadingBusinesses
            ? const LoadingWidget(message: '사업장 정보를 불러오는 중...')
            : _myBusinesses.isEmpty
                ? _buildNoBusinessState()
                : Column(
                    children: [
                      _buildBusinessSelector(),
                      Expanded(
                        child: _isLoading
                            ? const LoadingWidget(message: '업무 유형을 불러오는 중...')
                            : _workTypes.isEmpty
                                ? _buildEmptyState()
                                : _buildWorkTypeList(),
                      ),
                    ],
                  ),
    );
  }

  /// ✨ 세련된 사업장 선택기
  Widget _buildBusinessSelector() {
    final theme = Theme.of(context);
    
    if (_myBusinesses.length == 1) {
      return Container(
        margin: ResponsiveHelper.cardPadding(context),
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.primaryColor.withValues(alpha: 0.1),
              theme.primaryColor.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.primaryColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            _selectedBusiness?.mainImageUrl != null
                ? ImageHelper.buildCachedImage(
                    _selectedBusiness!.mainImageUrl!,
                    width: ResponsiveHelper.spacing(context, 48),
                    height: ResponsiveHelper.spacing(context, 48),
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(12),
                    memCacheWidth: 96,
                  )
                : Container(
                    width: ResponsiveHelper.spacing(context, 48),
                    height: ResponsiveHelper.spacing(context, 48),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.business,
                      color: theme.primaryColor,
                      size: ResponsiveHelper.iconSize(context, 24),
                    ),
                  ),
            SizedBox(width: ResponsiveHelper.spacing(context, 16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '현재 사업장',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    _selectedBusiness?.name ?? '',
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: ResponsiveHelper.cardPadding(context),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.grey500.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AppSelectField<BusinessModel>(
        value: _selectedBusiness,
        hintText: '사업장을 선택하세요',
        sheetTitle: '사업장 선택',
        items: _myBusinesses,
        labelOf: (b) => b.name,
        prefixIcon: Icons.business,
        onChanged: (value) {
          if (value != null) {
            setState(() => _selectedBusiness = value);
            _loadWorkTypes();
          }
        },
      ),
    );
  }

  /// ✨ 세련된 사업장 없음 상태
  Widget _buildNoBusinessState() {
    final theme = Theme.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.business_outlined,
              size: ResponsiveHelper.iconSize(context, 80),
              color: theme.primaryColor.withValues(alpha: 0.5),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          Text(
            '등록된 사업장이 없습니다',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '사업장을 먼저 등록해주세요',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 세련된 업무 유형 없음 상태
  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.work_outline,
      title: '등록된 업무 유형이 없습니다',
      subtitle: '상단의 + 버튼을 눌러 업무 유형을 추가하세요',
    );
  }

  /// 업무 유형 리스트 — 섹션 카드 방식 (앱 디자인 통일)
  Widget _buildWorkTypeList() {
    final theme = Theme.of(context);

    return ListView(
      padding: ResponsiveHelper.listPadding(context),
      children: [
        // 전체 항목을 하나의 섹션 카드에 묶음
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
                            // 아이콘 — 그림자 없이 깔끔하게
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
                            // 이름만 (순서 배지 제거 — 위치가 순서를 나타냄)
                            Expanded(
                              child: Text(
                                workType.name,
                                style: ResponsiveHelper.bodyStyle(context)
                                    .copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // 더보기 메뉴
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
                    // 마지막 항목 아래는 구분선 없음
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
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
      ],
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
              onTap: () => _handleMenuAction('moveUp', workType, index, isFirst, isLast),
            ),
          if (!isLast)
            AppMenuSheetItem(
              icon: Icons.arrow_downward,
              label: '아래로 이동',
              color: theme.primaryColor,
              onTap: () => _handleMenuAction('moveDown', workType, index, isFirst, isLast),
            ),
        ],
        [
          AppMenuSheetItem(
            icon: Icons.info_outline,
            label: '상세 정보',
            color: AppColors.info,
            onTap: () => _handleMenuAction('detail', workType, index, isFirst, isLast),
          ),
          AppMenuSheetItem(
            icon: Icons.edit,
            label: '아이콘수정',
            color: AppColors.warning,
            onTap: () => _handleMenuAction('edit', workType, index, isFirst, isLast),
          ),
        ],
        [
          AppMenuSheetItem(
            icon: Icons.delete,
            label: '삭제',
            color: AppColors.error,
            isDanger: true,
            onTap: () => _handleMenuAction('delete', workType, index, isFirst, isLast),
          ),
        ],
      ],
    );
  }

  /// 메뉴 액션 처리
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

  /// 상세 화면으로 이동
  Future<void> _openDetailScreen(BusinessWorkTypeModel workType, {bool initialEditMode = false}) async {  // ⭐ 파라미터 추가
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkTypeDetailScreen(
          workType: workType,
          initialEditMode: initialEditMode,  // ⭐ 전달
        ),
      ),
    );
    
    // 변경사항이 있으면 목록 새로고침
    if (result == true) {
      _loadWorkTypes();
    }
  }
  
}
