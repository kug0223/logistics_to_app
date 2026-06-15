import 'package:flutter/material.dart';

import '../../models/core/contract_template_model.dart';
import '../../services/contract_template_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import 'contract_template_edit_screen.dart';
import 'contract_template_preview_screen.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/loading_widget.dart';
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
  bool _loading = true;
  bool _isDuplicating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    _templates = await _service.getTemplates(widget.businessId);
    if (mounted) setState(() => _loading = false);
  }

  // ── 새 템플릿: 유형 선택 바텀시트 먼저 표시 ──
  Future<void> _showTypeSelector() async {
    final selectedType = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _TypeSelectorSheet(),
    );
    if (selectedType == null || !mounted) return;
    _openEditor(templateType: selectedType);
  }

  Future<void> _openEditor({
    ContractTemplateModel? template,
    String? templateType,
  }) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ContractTemplateEditScreen(
          businessId: widget.businessId,
          template: template,
          initialTemplateType: templateType,
        ),
      ),
    );
    if (result == true) _load();
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
      ToastHelper.showError('복사에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isDuplicating = false);
    }
  }

  Future<void> _delete(ContractTemplateModel t) async {
    final ok = await DialogHelper.showDeleteConfirm(
      context,
      itemName: '"${t.name}" 템플릿',
    );
    if (ok != true || !mounted) return;
    try {
      await _service.deleteTemplate(
          businessId: widget.businessId, templateId: t.id);
      if (mounted) { ToastHelper.showSuccess('템플릿이 삭제되었습니다'); _load(); }
    } catch (e) {
      if (mounted) ToastHelper.showError('삭제에 실패했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '근로계약서 관리',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showTypeSelector,
        backgroundColor: theme.primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('새 템플릿',
            style: ResponsiveHelper.smallStyle(context, color: Colors.white)),
      ),
      body: _loading
          ? const LoadingWidget()
          : _templates.isEmpty
              ? _buildEmpty(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: ResponsiveHelper.listPadding(context,
                        extra: 72), // FAB 높이 고려
                    itemCount: _templates.length,
                    itemBuilder: (ctx, i) => _TemplateCard(
                      template: _templates[i],
                      onEdit: () => _openEditor(template: _templates[i]),
                      onPreview: () => _openPreview(_templates[i]),
                      onDuplicate: () => _duplicate(_templates[i]),
                      onDelete: () => _delete(_templates[i]),
                    ),
                  ),
                ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.description_outlined,
      title: '등록된 템플릿이 없습니다',
      subtitle: '+ 새 템플릿을 눌러 계약서 유형을 선택하세요.',
    );
  }
}

// ─── 유형 선택 바텀시트 ────────────────────────────────────────────

class _TypeSelectorSheet extends StatelessWidget {
  const _TypeSelectorSheet();

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
                '어떤 계약서 유형인가요?',
                style: ResponsiveHelper.titleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
              Text(
                '선택한 유형에 맞는 가이드 조항이 자동으로 채워집니다.\n'
                '이후 사업장 상황에 맞게 자유롭게 수정하세요.',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey500),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 20)),

              // ── 단기 일용직 ──
              _TypeCard(
                type: ContractTemplateType.daily,
                icon: Icons.calendar_today_outlined,
                iconColor: AppColors.info,
                bgColor: AppColors.infoBg,
                title: '단기 일용직 근로계약서',
                subtitle: '하루~수주 단기 알바에 적합',
                points: const [
                  '일급·시급 기준 임금 조항',
                  '산재보험 필수 + 4대보험 조건 안내',
                  '주휴수당 적용 조건 포함',
                  '해고예고·임금명세서 의무 조항',
                  '5인 이상/미만 분기 가이드 포함',
                ],
                onTap: () =>
                    Navigator.pop(context, ContractTemplateType.daily),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              // ── 기간제 ──
              _TypeCard(
                type: ContractTemplateType.period,
                icon: Icons.date_range_outlined,
                iconColor: AppColors.success,
                bgColor: AppColors.successBg,
                title: '기간제 근로계약서 (장기)',
                subtitle: '1개월~2년 장기 계약에 적합',
                points: const [
                  '4대보험 전부 적용 조항',
                  '연차유급휴가·퇴직급여 조항',
                  '2년 초과 시 무기계약 전환 명시',
                  '수습기간 감액 조항 포함',
                  '기간제법 차별금지 조항',
                ],
                onTap: () =>
                    Navigator.pop(context, ContractTemplateType.period),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              // ── 업무위탁 ──
              _TypeCard(
                type: ContractTemplateType.outsource,
                icon: Icons.handshake_outlined,
                iconColor: AppColors.warning,
                bgColor: AppColors.warningBg,
                title: '업무위탁계약서 (3.3% 도급)',
                subtitle: '독립 수행 · 사업소득자에 적합',
                points: const [
                  '사업소득세 3.3% 원천징수 조항',
                  '4대보험 미적용 및 자가 납부 안내',
                  '독립성 보장·지휘명령 배제 조항',
                  '결과물 귀속·지식재산권 조항',
                  '위장도급 주의 법적 고지 포함',
                ],
                warning:
                    '실질적으로 지휘·감독을 받는 경우 근로자로 판단될 수 있으며, '
                    '위장도급 적발 시 4대보험 소급 부과·벌금 등 제재가 있습니다.',
                onTap: () =>
                    Navigator.pop(context, ContractTemplateType.outsource),
              ),

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
      ),  // Container
    );  // ConstrainedBox
  }
}

class _TypeCard extends StatelessWidget {
  final String type;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String title;
  final String subtitle;
  final List<String> points;
  final String? warning;
  final VoidCallback onTap;

  const _TypeCard({
    required this.type,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.onTap,
    this.warning,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.grey200),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: ResponsiveHelper.bodyStyle(context)
                                .copyWith(fontWeight: FontWeight.w700)),
                        SizedBox(
                            height: ResponsiveHelper.spacing(context, 2)),
                        Text(subtitle,
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey500)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      color: AppColors.grey400,
                      size: ResponsiveHelper.iconSize(context, 20)),
                ],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 10)),
              ...points.map((p) => Padding(
                    padding: EdgeInsets.only(
                        bottom: ResponsiveHelper.spacing(context, 3)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check,
                            size: ResponsiveHelper.iconSize(context, 13),
                            color: iconColor),
                        SizedBox(
                            width: ResponsiveHelper.spacing(context, 5)),
                        Expanded(
                          child: Text(p,
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.grey600)),
                        ),
                      ],
                    ),
                  )),
              if (warning != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Container(
                  padding: EdgeInsets.all(
                      ResponsiveHelper.spacing(context, 10)),
                  decoration: BoxDecoration(
                    color: AppColors.warningBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: ResponsiveHelper.iconSize(context, 14),
                          color: AppColors.warning),
                      SizedBox(
                          width: ResponsiveHelper.spacing(context, 6)),
                      Expanded(
                        child: Text(warning!,
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.warningDark)),
                      ),
                    ],
                  ),
                ),
              ],
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
        color: Colors.white,
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
              _Vdivider(),
              _ActionBtn(
                icon: Icons.copy_outlined,
                label: '복사',
                color: AppColors.grey600,
                onTap: onDuplicate,
              ),
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
