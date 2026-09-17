import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/contract_template_model.dart';
import '../../providers/user_provider.dart';
import '../../services/contract_template_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import 'contract_import_paste_screen.dart';
import 'contract_template_edit_screen.dart';
import 'contract_template_preview_screen.dart';
import '../../utils/navigation_helper.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/notification_badge.dart';
import '../common/notification_screen.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/dialogs/contract_template_type_selector_sheet.dart';
import '../../widgets/dialogs/styled_dialog.dart';

class ContractTemplateListScreen extends StatefulWidget {
  final String businessId;

  const ContractTemplateListScreen({super.key, required this.businessId});

  @override
  State<ContractTemplateListScreen> createState() =>
      _ContractTemplateListScreenState();
}

class _ContractTemplateListScreenState
    extends State<ContractTemplateListScreen> {
  final _service = ContractTemplateService();
  List<ContractTemplateModel> _templates = [];
  bool _loading = false; // initState → _load() 가드 통과를 위해 false 초기화
  bool _isDuplicating = false;

  /// [UX-P2-04] 복사해올 수 있는 다른 사업장 수.
  /// 0이면 생성 방법 시트에서 "다른 사업장에서 가져오기" 타일을 숨긴다 —
  /// 소스 후보는 callableGetMyBusiness(adminIds) 기반이라 SUB_ADMIN이나
  /// 단일 사업장 관리자에게는 항상 0이고, 탭하면 빈 시트만 보게 된다.
  /// 시트를 열기 전에 확정해야 타일이 깜빡였다 사라지는 flash가 없다.
  /// 조회 실패 시 0 유지(fail-closed) — 당겨서 새로고침으로 복구 가능.
  int _otherBusinessCount = 0;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // [AUTHZ.2] SUB_ADMIN canManageContract 진입 가드
      // Settings/Home의 메뉴 미노출 철학 동일 — 어떤 경로로 진입해도 권한 없으면 차단
      final up = context.read<UserProvider>();
      if (up.checkCurrentBusiness((p) => p.canManageContract) != PermissionCheck.allowed) {
        ToastHelper.showWarning('계약서 관리 권한이 없습니다');
        Navigator.pop(context);
        return;
      }
      _load();
    });
  }

  Future<void> _load() async {
    if (!mounted || _loading) return;
    setState(() => _loading = true);
    try {
      if (kDebugMode) debugPrint('📂 [ContractTemplateListScreen] businessId=${widget.businessId}');
      // [UX-P2-04] 템플릿 목록과 소스 사업장 수를 병렬 조회 —
      //   생성 방법 시트를 열기 전에 타일 노출 여부가 확정되도록 한다.
      //   _countOtherBusinesses는 자체 catch로 0을 반환하므로
      //   이 조회가 템플릿 로드를 실패시키지 않는다.
      final results = await Future.wait([
        _service.getTemplates(widget.businessId),
        _countOtherBusinesses(),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = results[0] as List<ContractTemplateModel>;
        _otherBusinessCount = results[1] as int;
      });
    } catch (e) {
      debugPrint('❌ 템플릿 로드 실패: $e');
      if (mounted) ToastHelper.showError('템플릿 목록을 불러오지 못했습니다');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// [UX-P2-04] 복사 소스가 될 수 있는 다른 사업장 수.
  ///
  /// _OtherBusinessTemplateSheet와 **동일한 소스 정의**를 쓴다 —
  /// getMyBusiness(= callableGetMyBusiness, adminIds 기반)에서 현재 사업장 제외.
  /// 권한 범위를 넓히지 않으며, 노출 판단에만 쓰인다.
  Future<int> _countOtherBusinesses() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return 0;
      final businesses = await FirestoreService().getMyBusiness(uid);
      return businesses.where((b) => b.id != widget.businessId).length;
    } catch (e) {
      debugPrint('⚠️ [다른 사업장 수 조회 실패] 타일 숨김 처리: $e');
      return 0; // fail-closed — 빈 시트로 유도하지 않는다
    }
  }

  // ── 새 템플릿: 생성 방법 선택 ──────────────────────────────────
  Future<void> _showCreationMethodChooser() async {
    final method = await DialogHelper.showSheet<_CreationMethod>(
      context,
      isScrollControlled: true,
      builder: (ctx) =>
          _CreationMethodSheet(showCrossBusiness: _otherBusinessCount > 0),
    );
    if (method == null || !mounted) return;

    switch (method) {
      case _CreationMethod.importExisting:
        // 기존 계약서로 시작: 유형 선택 → PasteScreen
        // [F-02] 붙여넣은 조항이 그대로 쓰이므로 유형은 분류 역할만 한다.
        final type = await _pickTemplateType(
            ContractTemplateTypePurpose.importClassification);
        if (type == null || !mounted) return;
        await _startImportFlow(type);

      case _CreationMethod.defaultTemplate:
        // ALfit 기본 조항: 유형 선택 → 참고용 기본 조항이 채워진 EditScreen
        // [F-02] 이 경로에서만 유형이 실제로 로드될 조항을 결정한다.
        final type = await _pickTemplateType(
            ContractTemplateTypePurpose.defaultCreation);
        if (type == null || !mounted) return;
        await _openEditor(templateType: type);

      case _CreationMethod.copyFromBusiness:
        // 다른 사업장에서 가져오기
        await _showCrossBusinessCopy();

      case _CreationMethod.blank:
        // 빈 템플릿으로 시작: 유형 선택 → 빈 EditScreen
        // [F-02] initialArticles: [] 를 넘기므로 기본 조항이 로드되지 않는다 —
        //   Import와 마찬가지로 유형은 분류 역할만 한다.
        final type = await _pickTemplateType(
            ContractTemplateTypePurpose.blankClassification);
        if (type == null || !mounted) return;
        await _openEditor(templateType: type, initialArticles: []);
    }
  }

  /// 유형 선택 시트만 표시 — String(templateType) 반환.
  /// [purpose]는 같은 선택이 경로마다 다른 효과를 갖는다는 사실을
  /// 시트 문구에 반영하기 위한 것이다.
  Future<String?> _pickTemplateType(ContractTemplateTypePurpose purpose) {
    return DialogHelper.showSheet<String>(
      context,
      isScrollControlled: true,
      builder: (ctx) => ContractTemplateTypeSelectorSheet(purpose: purpose),
    );
  }

  /// 기존 계약서 Import Flow 시작
  Future<void> _startImportFlow(String templateType) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ContractImportPasteScreen(
          businessId: widget.businessId,
          templateType: templateType,
        ),
      ),
    );
    if (result == true && mounted) _load();
  }

  /// 다른 사업장 템플릿 복사
  Future<void> _showCrossBusinessCopy() async {
    final selected = await DialogHelper.showSheet<ContractTemplateModel>(
      context,
      isScrollControlled: true,
      builder: (ctx) => _OtherBusinessTemplateSheet(
        excludeBusinessId: widget.businessId,
      ),
    );
    if (selected == null || !mounted) return;

    try {
      final copy = await _service.duplicateTemplateTo(
          selected, widget.businessId);
      if (!mounted) return;
      ToastHelper.showSuccess('"${copy.name}" 템플릿이 복사되었습니다');
      await _load();
      if (mounted) await _openEditor(template: copy);
    } catch (e) {
      if (mounted) ToastHelper.showError('가져오기에 실패했습니다');
    }
  }

  Future<void> _openEditor({
    ContractTemplateModel? template,
    String? templateType,
    List<ContractArticle>? initialArticles,
  }) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ContractTemplateEditScreen(
          businessId: widget.businessId,
          template: template,
          initialTemplateType: templateType,
          initialArticles: initialArticles,
        ),
      ),
    );
    if (result == true && mounted) _load(); // [BUG-수정] W-M-1: async gap 후 mounted 체크
  }

  void _openPreview(ContractTemplateModel t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContractTemplatePreviewScreen(template: t),
      ),
    );
  }

  Future<void> _duplicate(ContractTemplateModel t) async {
    if (_isDuplicating) return;
    setState(() => _isDuplicating = true);
    try {
      final copy = await _service.duplicateTemplate(t);
      if (!mounted) return;
      ToastHelper.showSuccess('"${copy.name}" 템플릿이 복사되었습니다');
      await _load();
      if (mounted) {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ContractTemplateEditScreen(
              businessId: widget.businessId,
              template: copy,
            ),
          ),
        );
        if (result == true && mounted) _load();
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('복사에 실패했습니다'); // [BUG-수정] W-L-1: catch 블록 Toast mounted 체크 추가
    } finally {
      if (mounted) setState(() => _isDuplicating = false);
    }
  }

  Future<void> _delete(ContractTemplateModel t) async {
    if (_isDeleting) return;
    setState(() => _isDeleting = true);
    try {
      final ok = await DialogHelper.showDeleteConfirm(
        context,
        itemName: '"${t.name}" 템플릿',
      );
      if (ok != true || !mounted) return;
      await _service.deleteTemplate(
          businessId: widget.businessId, templateId: t.id);
      if (mounted) { ToastHelper.showSuccess('템플릿이 삭제되었습니다'); _load(); }
    } catch (e) {
      if (mounted) ToastHelper.showError('삭제에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      // [UX-P2-05] 진입 메뉴(설정›계약›"계약서 템플릿")와 제목을 일치시킨다.
      //   기존 '근로계약서 관리'는 실제 계약 목록 화면인
      //   AdminContractManagement('계약서 관리')와 혼동을 만들었다.
      title: '계약서 템플릿',
      actions: [
        IconButton(
          icon: const Icon(Icons.home_outlined),
          color: AppColors.textSecondary,
          onPressed: () => NavigationHelper.goHome(context),
          tooltip: '홈',
        ),
        NotificationBadge(
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            color: AppColors.textSecondary,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            tooltip: '알림',
          ),
        ),
      ],
      body: _loading
          ? const LoadingWidget()
          : _templates.isEmpty
              ? _buildEmpty(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: ResponsiveHelper.listPadding(context),
                    itemCount: _templates.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == _templates.length) {
                        return _buildAddButton(context);
                      }
                      return _TemplateCard(
                        template: _templates[i],
                        onEdit: () => _openEditor(template: _templates[i]),
                        onPreview: () => _openPreview(_templates[i]),
                        onDuplicate: () => _duplicate(_templates[i]),
                        onDelete: () => _delete(_templates[i]),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.only(
        top: ResponsiveHelper.spacing(context, 8),
        bottom: ResponsiveHelper.spacing(context, 16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showCreationMethodChooser,
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
                  '새 계약서 템플릿 추가',
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
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return AppEmptyState(
      icon: Icons.description_outlined,
      title: '등록된 템플릿이 없습니다',
      subtitle: '계약서 템플릿을 추가하고 근로계약을 관리해보세요',
      action: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _showCreationMethodChooser,
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
                    '새 계약서 템플릿 추가',
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
}

// ─── 생성 방법 enum ────────────────────────────────────────────────

enum _CreationMethod {
  importExisting,   // 기존 계약서로 시작 (Paste → Parser)
  defaultTemplate,  // ALfit 기본 조항
  copyFromBusiness, // 다른 사업장에서 가져오기
  blank,            // 빈 템플릿으로 시작
}

// ─── 생성 방법 선택 시트 ──────────────────────────────────────────

class _CreationMethodSheet extends StatelessWidget {
  /// [UX-P2-04] 복사 가능한 다른 사업장이 있을 때만 해당 타일을 노출한다.
  final bool showCrossBusiness;
  const _CreationMethodSheet({required this.showCrossBusiness});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 20),
              ResponsiveHelper.spacing(context, 8),
              ResponsiveHelper.spacing(context, 20),
              ResponsiveHelper.spacing(context, 16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 드래그 핸들
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: EdgeInsets.only(
                        bottom: ResponsiveHelper.spacing(context, 20)),
                    decoration: BoxDecoration(
                      color: AppColors.grey300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  '새 템플릿 만들기',
                  style: ResponsiveHelper.titleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                Text(
                  '시작 방법을 선택해 주세요.',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey500),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                _MethodTile(
                  icon: Icons.upload_file_outlined,
                  iconColor: AppColors.info,
                  bgColor: AppColors.infoBg,
                  title: '기존 계약서로 시작',
                  subtitle: '한글·Word·PDF에서 복사한 내용을 붙여넣어 조항으로 나눕니다',
                  onTap: () => Navigator.pop(context, _CreationMethod.importExisting),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 10)),

                _MethodTile(
                  icon: Icons.auto_awesome_outlined,
                  iconColor: AppColors.success,
                  bgColor: AppColors.successBg,
                  // [RB-02] '법령 기반' + '자동' 조합은 ALfit이 법적 적합성을
                  //   보증하는 인상을 준다. ALfit은 계약 내용을 대신 확정하거나
                  //   적법성을 보증하지 않는 작성 도구이므로 참고용임을 명시한다.
                  title: 'ALfit 기본 조항',
                  subtitle: '작성을 시작할 참고용 기본 조항을 불러옵니다. 사업장에 맞게 확인·수정하세요',
                  onTap: () => Navigator.pop(context, _CreationMethod.defaultTemplate),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 10)),

                _MethodTile(
                  icon: Icons.note_add_outlined,
                  iconColor: AppColors.grey500,
                  bgColor: AppColors.grey100,
                  title: '빈 템플릿으로 시작',
                  subtitle: '조항을 처음부터 직접 작성합니다',
                  onTap: () => Navigator.pop(context, _CreationMethod.blank),
                ),

                // [UX-P2-04] 조건부 기능은 최하단 — 복사할 사업장이 있을 때만 노출.
                if (showCrossBusiness) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                  _MethodTile(
                    icon: Icons.business_outlined,
                    iconColor: AppColors.warning,
                    bgColor: AppColors.warningBg,
                    title: '다른 사업장에서 가져오기',
                    subtitle: '내가 관리하는 다른 사업장의 템플릿을 복사합니다',
                    onTap: () =>
                        Navigator.pop(context, _CreationMethod.copyFromBusiness),
                  ),
                ],

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('취소',
                        style: ResponsiveHelper.bodyStyle(context,
                            color: AppColors.grey500)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MethodTile({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.grey200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    color: iconColor,
                    size: ResponsiveHelper.iconSize(context, 22)),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: ResponsiveHelper.bodyStyle(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                    Text(
                      subtitle,
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey500),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.grey400,
                  size: ResponsiveHelper.iconSize(context, 20)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 다른 사업장 템플릿 선택 시트 ─────────────────────────────────

class _OtherBusinessTemplateSheet extends StatefulWidget {
  final String excludeBusinessId;

  const _OtherBusinessTemplateSheet({required this.excludeBusinessId});

  @override
  State<_OtherBusinessTemplateSheet> createState() =>
      _OtherBusinessTemplateSheetState();
}

class _OtherBusinessTemplateSheetState
    extends State<_OtherBusinessTemplateSheet> {
  final _service = ContractTemplateService();
  List<ContractTemplateModel> _templates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOtherBusinessTemplates();
  }

  Future<void> _loadOtherBusinessTemplates() async {
    try {
      // 현재 사용자의 모든 사업장 목록 조회
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final firestoreService = FirestoreService();
      final businesses = await firestoreService.getMyBusiness(uid);

      // 현재 사업장 제외한 다른 사업장들의 템플릿 수집
      final others = businesses.where((b) => b.id != widget.excludeBusinessId).toList();
      if (others.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final allTemplates = <ContractTemplateModel>[];
      for (final biz in others) {
        try {
          final tpls = await _service.getTemplates(biz.id);
          // [5.11] legacy 분류는 다른 사업장으로 복사할 수 없으므로 후보에서 제외.
          //   골랐다가 실패하는 항목을 보여주지 않는다.
          allTemplates.addAll(
              ContractTemplateModel.selectableForNewContract(tpls));
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _templates = allTemplates;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ 다른 사업장 템플릿 조회 실패: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 핸들 + 타이틀
              Padding(
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.spacing(context, 20),
                  ResponsiveHelper.spacing(context, 8),
                  ResponsiveHelper.spacing(context, 20),
                  ResponsiveHelper.spacing(context, 12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: EdgeInsets.only(
                            bottom: ResponsiveHelper.spacing(context, 20)),
                        decoration: BoxDecoration(
                          color: AppColors.grey300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      '다른 사업장 템플릿 가져오기',
                      style: ResponsiveHelper.titleStyle(context)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      '선택한 템플릿이 이 사업장으로 복사됩니다.',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey500),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: AppColors.grey100),

              // 목록
              Flexible(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _templates.isEmpty
                        ? Padding(
                            padding: EdgeInsets.all(
                                ResponsiveHelper.spacing(context, 32)),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.business_outlined,
                                    size: 48, color: AppColors.grey300),
                                SizedBox(
                                    height: ResponsiveHelper.spacing(
                                        context, 12)),
                                Text(
                                  '가져올 수 있는 템플릿이 없습니다',
                                  style: ResponsiveHelper.bodyStyle(context,
                                      color: AppColors.grey500),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(
                                    height: ResponsiveHelper.spacing(
                                        context, 4)),
                                Text(
                                  '다른 사업장에 등록된 템플릿이 없거나\n관리 중인 사업장이 이 사업장 하나뿐입니다.',
                                  style: ResponsiveHelper.smallStyle(context,
                                      color: AppColors.grey400),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: EdgeInsets.symmetric(
                              horizontal:
                                  ResponsiveHelper.spacing(context, 16),
                              vertical: ResponsiveHelper.spacing(context, 8),
                            ),
                            itemCount: _templates.length,
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, color: AppColors.grey100),
                            itemBuilder: (ctx, i) {
                              final t = _templates[i];
                              return ListTile(
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal:
                                      ResponsiveHelper.spacing(context, 4),
                                  vertical:
                                      ResponsiveHelper.spacing(context, 4),
                                ),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.grey100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.description_outlined,
                                      color: AppColors.grey500,
                                      size: ResponsiveHelper.iconSize(
                                          context, 20)),
                                ),
                                title: Text(
                                  t.name,
                                  style: ResponsiveHelper.bodyStyle(context)
                                      .copyWith(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  '${ContractTemplateType.label(t.templateType)} · 조항 ${t.articles.length}개',
                                  style: ResponsiveHelper.tinyStyle(context,
                                      color: AppColors.grey500),
                                ),
                                trailing: Icon(Icons.chevron_right,
                                    color: AppColors.grey400,
                                    size: ResponsiveHelper.iconSize(
                                        context, 20)),
                                onTap: () => Navigator.pop(context, t),
                              );
                            },
                          ),
              ),

              // 취소
              Padding(
                padding: EdgeInsets.fromLTRB(
                  0,
                  ResponsiveHelper.spacing(context, 4),
                  0,
                  ResponsiveHelper.spacing(context, 8),
                ),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('취소',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.grey500)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 템플릿 카드 ──────────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  final ContractTemplateModel template;
  final VoidCallback onEdit;
  final VoidCallback onPreview;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onPreview,
    required this.onDuplicate,
    required this.onDelete,
  });

  Color _typeColor(BuildContext context) {
    switch (template.templateType) {
      case ContractTemplateType.daily:     return AppColors.info;
      case ContractTemplateType.period:    return AppColors.success;
      case ContractTemplateType.outsource: return AppColors.warning;
      default: return Theme.of(context).primaryColor;
    }
  }

  Color _typeBg() {
    switch (template.templateType) {
      case ContractTemplateType.daily:     return AppColors.infoBg;
      case ContractTemplateType.period:    return AppColors.successBg;
      case ContractTemplateType.outsource: return AppColors.warningBg;
      default: return AppColors.grey100;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeColor = _typeColor(context);
    return Container(
      margin:
          EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 14),
              ResponsiveHelper.spacing(context, 8),
              ResponsiveHelper.spacing(context, 10),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.description_outlined,
                      color: typeColor,
                      size: ResponsiveHelper.iconSize(context, 20)),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              template.name,
                              style: ResponsiveHelper.bodyStyle(context)
                                  .copyWith(fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                          height: ResponsiveHelper.spacing(context, 4)),
                      Row(
                        children: [
                          // 유형 배지
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal:
                                  ResponsiveHelper.spacing(context, 7),
                              vertical:
                                  ResponsiveHelper.spacing(context, 2),
                            ),
                            decoration: BoxDecoration(
                              color: _typeBg(),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              ContractTemplateType.label(
                                  template.templateType),
                              style: ResponsiveHelper.tinyStyle(context)
                                  .copyWith(
                                color: typeColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(
                              width: ResponsiveHelper.spacing(context, 6)),
                          Flexible(
                            child: Text(
                              '조항 ${template.articles.length}개 · '
                              '${_fmtDate(template.updatedAt ?? template.createdAt)}',
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.grey400),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // [UX-P3-04] 조항 제목 미리보기 — 템플릿이 여러 개일 때
          //   Preview를 열지 않고도 내용을 구분할 수 있게 한다.
          //   SelectorDialog와 동일한 "앞 2개 제목 · 외 N개" 패턴.
          //   본문(article.content)은 노출하지 않는다 — 제목만.
          Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 16),
              0,
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 12),
            ),
            child: Text(
              _articleSummary(),
              style: ResponsiveHelper.tinyStyle(context,
                  color: template.articles.isEmpty
                      ? AppColors.grey400
                      : AppColors.grey500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // 액션 버튼 행
          const Divider(height: 1, color: AppColors.grey100),
          Row(
            children: [
              _ActionBtn(
                icon: Icons.visibility_outlined,
                label: '미리보기',
                color: AppColors.grey600,
                onTap: onPreview,
              ),
              // [5.11] legacy 분류는 복사로 증식시키지 않는다 —
              //   신규 계약에 쓸 수 없는 템플릿을 복제할 제품적 가치가 없고,
              //   복사 경로가 신규 생성 금지의 우회로가 된다.
              //   편집·미리보기·삭제는 그대로 두어 기존 데이터 접근권을 지킨다.
              if (template.isSupportedForNewUse) ...[
                _Vdivider(),
                _ActionBtn(
                  icon: Icons.copy_outlined,
                  label: '복사',
                  color: AppColors.grey600,
                  onTap: onDuplicate,
                ),
              ],
              _Vdivider(),
              _ActionBtn(
                icon: Icons.edit_outlined,
                label: '편집',
                color: theme.primaryColor,
                onTap: onEdit,
              ),
              _Vdivider(),
              _ActionBtn(
                icon: Icons.delete_outline,
                label: '삭제',
                color: AppColors.errorMedium,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) => FormatHelper.formatDateDot(d);

  /// [UX-P3-04] 조항 제목 요약 — "제4조 (수당) · 제5조 (휴게) 외 6개"
  ///
  /// 조항이 없어도 "빈 계약서"라고 하지 않는다.
  /// ALfit이 자동 작성하는 제1~3조는 별도로 존재하므로,
  /// 여기서 비어 있는 것은 "관리자가 덧붙인 추가 조항"뿐이다.
  String _articleSummary() {
    final articles = template.articles;
    if (articles.isEmpty) return '추가 조항 없음';

    final head = articles
        .take(2)
        .map((a) => a.title.trim().isEmpty ? '(제목 없음)' : a.title.trim())
        .join(' · ');
    final rest = articles.length - 2;
    return rest > 0 ? '$head 외 $rest개' : head;
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 10)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: color),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text(label,
                  style: ResponsiveHelper.tinyStyle(context, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Vdivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 36, color: AppColors.grey100);
}
