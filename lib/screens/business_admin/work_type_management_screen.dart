import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import '../../models/core/business_work_type_model.dart';
import '../../providers/user_provider.dart';
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
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/notification_badge.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../utils/navigation_helper.dart';
import '../common/notification_screen.dart';
import '../../models/core/to_model.dart';
import '../../utils/text_layout.dart';

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
  bool _fetchInProgress = false;
  bool _isReordering = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadWorkTypes();
    });
  }

  Future<void> _loadWorkTypes() async {
    if (_fetchInProgress) return;
    _fetchInProgress = true;
    if (!_isLoading) setState(() => _isLoading = true);
    try {
      final workTypes =
          await _firestoreService.getBusinessWorkTypes(widget.businessId);
      if (!mounted) return;
      _fetchInProgress = false;
      setState(() {
        _workTypes = workTypes;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 업무 유형 로드 실패: $e');
      if (!mounted) return;
      _fetchInProgress = false;
      setState(() => _isLoading = false);
      ToastHelper.showError('업무를 불러올 수 없습니다');
    }
  }

  /// 업무 유형 추가
  Future<void> _showAddDialog() async {
    // [R7-P4.4E.5.2] 쓰기는 **여기가** 계속 소유한다 — businessId 도 여기 것이다.
    //   시트에 넘기는 것은 "저장을 수행해 달라" 는 요청뿐이고, 시트는 그
    //   결과로 닫을지 말지만 정한다. 실패하면 시트가 열린 채 남아 관리자가
    //   고른 이름·아이콘·색이 살아 있다.
    String? newId;
    Map<String, dynamic>? draftUsed;
    final saved = await AddWorkTypeSheet.show(
      context,
      onSubmit: (draft) async {
        draftUsed = draft;
        newId = await _firestoreService.addBusinessWorkType(
          businessId: widget.businessId,
          name: draft['name'] as String,
          icon: (draft['icon'] as String?) ?? '',
          color: draft['iconColor'] as String? ?? '#FFFFFF',
          backgroundColor: draft['backgroundColor'] as String?,
        );
        return newId != null;
      },
    );
    // 저장되지 않았으면(사용자가 닫았거나 실패 후 직접 닫았거나) 아무것도
    //   하지 않는다 — 목록도 readiness 도 건드릴 이유가 없다.
    if (saved != true || !mounted) return;

    final result = draftUsed ?? const <String, dynamic>{};
    // [MOUNTED-02 수정] addBusinessWorkType await 후 mounted 체크를 &&로만 처리하면
    // newId == null일 때 mounted 미체크 — 명시적 가드로 통일
    if (!mounted) return;
    if (newId != null) {
      await _loadWorkTypes();
      if (!mounted) return;

      // `newId` 는 캡처된 지역 변수라 promotion 이 되지 않는다 —
      //   이 분기는 `newId != null` 안이므로 여기서 고정해 쓴다.
      final createdId = newId!;
      final newWorkType = _workTypes.firstWhere(
        (wt) => wt.id == createdId,
        orElse: () => BusinessWorkTypeModel(
          id: createdId,
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
        barrierDismissible: false,
        builder: (ctx) => StyledDialog(
          title: '등록 완료!',
          subtitle: '업무가 성공적으로 등록되었습니다',
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

  // [WORKTYPE-IDENTITY] 업무 유형의 이름·아이콘은 등록 후 바꾸지 않는다 — 공고·지원·계약이 이 업무를
  //   이름·아이콘으로 저장해 두었고, 바꾸면 같은 업무가 다른 업무처럼 보인다. 다른 업무가 필요하면
  //   새 업무 유형을 만든다. 설명·사진은 상세 정보 화면에서 고친다(기존 공고에도 최신본이 보인다).

  /// 삭제 확인 다이얼로그
  Future<void> _confirmDelete(BusinessWorkTypeModel workType) async {
    if (_isDeleting) return;
    setState(() => _isDeleting = true);
    try {
      // [CF 이전 2026-07-13] callableGetTOsByBiz — statuses 배열로 서버 whereIn 처리
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetTOsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': widget.businessId,
        'statuses': [TOStatus.active, TOStatus.full, TOStatus.scheduled],
      });
      final activeTOsRaw = (result.data['tos'] as List? ?? [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

      final affectedCount = activeTOsRaw.where((data) {
        final details = (data['workDetails'] as List?)
            ?.whereType<Map>()
            .toList() ?? [];
        return details.any((d) => d['workType'] == workType.name);
      }).length;

      if (!mounted) return;

      if (affectedCount > 0) {
        final proceed = await showWorkTypeActivePostingsDialog(context, affectedCount: affectedCount);
        if (proceed != true || !mounted) return;
      }

      final confirmed = await showWorkTypeDeleteConfirmDialog(context, workTypeName: workType.name);

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
    } catch (e) {
      debugPrint('❌ 업무유형 삭제 실패: $e');
      if (mounted) ToastHelper.showError('삭제 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
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
    // [PERF-2026-07-16] bool 1개만 필요 → select으로 rebuild 범위 축소
    final canEdit = context.select<UserProvider, bool>((p) => p.can((perm) => perm.canManageTo));

    return AppPageScaffold(
      title: '업무 유형 관리',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadWorkTypes,
          color: AppColors.textSecondary,
          tooltip: '새로고침',
        ),
        IconButton(
          icon: const Icon(Icons.home_outlined),
          onPressed: () => NavigationHelper.goHome(context),
          color: AppColors.textSecondary,
          tooltip: '홈',
        ),
        NotificationBadge(
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            color: AppColors.textSecondary,
          ),
        ),
      ],
      body: _isLoading
          ? const LoadingWidget(message: '업무 유형을 불러오는 중...')
          : _workTypes.isEmpty
              ? _buildEmptyState(canEdit: canEdit)
              : _buildWorkTypeList(canEdit: canEdit),
    );
  }

  Widget _buildEmptyState({bool canEdit = true}) {
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

  Widget _buildWorkTypeList({bool canEdit = true}) {
    final theme = Theme.of(context);

    return ListView(
      padding: ResponsiveHelper.listPadding(context),
      children: [
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
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
                              // [DU484] grey400(흰 행 위 약 1.9 · 비텍스트 3:1 미달) → grey600(4.61 · 메뉴 열기 보조 행동 · DU396 과 같다).
                              icon: Icon(Icons.more_vert,
                                  color: AppColors.grey600,
                                  size: ResponsiveHelper.iconSize(context, 20)),
                              onPressed: () => _showWorkTypeMenuSheet(
                                  context, theme, workType, index, isFirst, isLast,
                                  canEdit: canEdit),
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
        // [AUTHZ.2] canEdit=false(canManageTo 없음)이면 추가 버튼 미노출
        if (canEdit) _buildListAddButton(),
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
    bool isLast, {
    bool canEdit = true,
  }) {
    AppMenuSheet.show(
      context: context,
      itemGroups: [
        if (canEdit && (!isFirst || !isLast))
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
        ],
        if (canEdit)
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

/// [DU325 seam] 업무 유형 삭제 1단계 — 진행 중 공고가 이 업무를 쓰면 묻는 창(표시만). 반환: 취소 false · 계속 true · 그 밖 null.
///   조회 · 권한 · writer 는 호출자(_confirmDelete)에 있다. 시험이 이 창만 직접 띄워 본다.
/// [DU325 스타일] 공용 셸(StyledDialog) — 바깥 탭으로 닫히지 않는다(barrierDismissible:false 유지). '계속'은 다음 확인으로 가는
///   일반 진행이라 brand(이전 빨간 글자는 손실 실행처럼 보였다).
Future<bool?> showWorkTypeActivePostingsDialog(BuildContext context, {required int affectedCount}) {
  final message = '이 업무를 사용하는 진행 중 공고가 $affectedCount개 있습니다.\n'
      '그 공고와 지원·확정 기록은 그대로이고 업무 안내도 계속 보입니다.\n'
      '새 공고에서만 이 업무를 고를 수 없게 됩니다. 계속하시겠습니까?';
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StyledDialog(
      title: '활성 공고 있음',
      icon: Icons.warning_amber_rounded,
      headerColor: AppColors.warningDark,
      content: Text(
        TextLayout.phrases(message),
        semanticsLabel: message,
        style: ResponsiveHelper.bodyStyle(ctx).copyWith(color: AppColors.textPrimary, height: 1.5),
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () => Navigator.pop(ctx, false),
        ),
        StyledDialogButton.primary(
          text: '계속',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
}

/// [DU325 seam] 업무 유형 삭제 2단계 — 최종 삭제 확인 창(표시만). 반환: 취소 false · 삭제 true · 그 밖 null.
/// [DU325 스타일] 공용 셸(StyledDialog) — 최종 손실 행동 '삭제'만 errorDark(danger). 결과 안내는 읽기용 보조색(빨강 남발 금지).
///   실제 효과는 isActive:false(호출자 writer) — 기존 공고 · 지원/확정 · 안내 보존 문구는 1단계와 이 창의 결과 안내에 그대로 있다.
Future<bool?> showWorkTypeDeleteConfirmDialog(BuildContext context, {required String workTypeName}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StyledDialog(
      title: '업무 유형 삭제',
      subtitle: '정말로 삭제하시겠습니까?',
      icon: Icons.delete_outline,
      headerColor: AppColors.errorDark,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            TextLayout.keepWords(workTypeName),
            semanticsLabel: workTypeName,
            style: ResponsiveHelper.bodyStyle(ctx).copyWith(
              color: Theme.of(ctx).primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(ctx, 8)),
          Text(
            TextLayout.keepWords('새 공고에서 이 업무를 고를 수 없게 됩니다'),
            semanticsLabel: '새 공고에서 이 업무를 고를 수 없게 됩니다',
            style: ResponsiveHelper.smallStyle(ctx, color: AppColors.textSecondary),
          ),
        ],
      ),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () => Navigator.pop(ctx, false),
        ),
        StyledDialogButton.danger(
          text: '삭제',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
}
