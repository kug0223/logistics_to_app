import 'package:flutter/material.dart';

import '../../models/core/contract_template_model.dart';
import '../../services/contract_template_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/notification_badge.dart';
import '../common/notification_screen.dart';

class ContractTemplateEditScreen extends StatefulWidget {
  final String businessId;
  final ContractTemplateModel? template;          // null이면 신규
  final String? initialTemplateType;              // 신규 시 선택된 유형

  const ContractTemplateEditScreen({
    super.key,
    required this.businessId,
    this.template,
    this.initialTemplateType,
  });

  @override
  State<ContractTemplateEditScreen> createState() =>
      _ContractTemplateEditScreenState();
}

class _ContractTemplateEditScreenState
    extends State<ContractTemplateEditScreen> {
  final _service = ContractTemplateService();
  late final TextEditingController _nameCtrl;
  late List<_ArticleEntry> _entries;
  late String _templateType;
  bool _saving = false;
  bool _hasChanges = false;

  bool get _isNew => widget.template == null;

  @override
  void initState() {
    super.initState();
    // 유형: 기존 템플릿 > 선택된 유형 > 기본(단기 일용직)
    _templateType = widget.template?.templateType
        ?? widget.initialTemplateType
        ?? ContractTemplateType.daily;

    _nameCtrl = TextEditingController(text: widget.template?.name ?? '');
    _nameCtrl.addListener(_onChanged);

    final sourceArticles = widget.template != null
        ? widget.template!.articles
        : ContractTemplateModel.defaultArticlesFor(_templateType);

    _entries = sourceArticles
        .map((a) => _ArticleEntry(
              titleCtrl: TextEditingController(text: a.title),
              contentCtrl: TextEditingController(text: a.content),
            ))
        .toList();
    for (final e in _entries) {
      e.titleCtrl.addListener(_onChanged);
      e.contentCtrl.addListener(_onChanged);
    }
  }

  void _onChanged() {
    if (!_hasChanges && mounted) setState(() => _hasChanges = true);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _scrollCtrl.dispose();
    for (final e in _entries) {
      e.titleCtrl.dispose();
      e.contentCtrl.dispose();
    }
    super.dispose();
  }

  void _addArticle() {
    final entry = _ArticleEntry(
      titleCtrl: TextEditingController(),
      contentCtrl: TextEditingController(),
    );
    entry.titleCtrl.addListener(_onChanged);
    entry.contentCtrl.addListener(_onChanged);
    setState(() {
      _entries.add(entry);
      _hasChanges = true;
    });
    // 새 항목으로 스크롤
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeArticle(int index) {
    setState(() {
      _entries[index].titleCtrl.dispose();
      _entries[index].contentCtrl.dispose();
      _entries.removeAt(index);
      _hasChanges = true;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ToastHelper.showWarning('템플릿 이름을 입력해주세요');
      return;
    }
    final articles = _entries
        .map((e) => ContractArticle(
              title: e.titleCtrl.text.trim(),
              content: e.contentCtrl.text.trim(),
            ))
        .where((a) => a.title.isNotEmpty || a.content.isNotEmpty)
        .toList();

    setState(() => _saving = true);
    try {
      if (_isNew) {
        await _service.createTemplate(
          businessId: widget.businessId,
          name: name,
          templateType: _templateType,
          articles: articles,
        );
      } else {
        await _service.updateTemplate(
          widget.template!.copyWith(
            name: name,
            templateType: _templateType,
            articles: articles,
            updatedAt: DateTime.now(),
          ),
        );
      }
      if (mounted) {
        ToastHelper.showSuccess(_isNew ? '템플릿이 저장되었습니다' : '템플릿이 수정되었습니다');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('저장에 실패했습니다');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  final _scrollCtrl = ScrollController();

  Future<bool> _confirmDiscard(BuildContext ctx) async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('편집 취소'),
        content: const Text('저장하지 않은 변경사항이 있습니다.\n나가시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('계속 편집')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('나가기', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final discard = await _confirmDiscard(context);
        if (!context.mounted) return;
        if (discard) nav.pop();
      },
      child: AppPageScaffold(
        title: _isNew ? '새 템플릿 만들기' : '템플릿 편집',
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
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Theme.of(context).primaryColor),
                  )
                : Text('저장',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.bold)),
          ),
        ],
      body: ListView(
        controller: _scrollCtrl,
        padding: ResponsiveHelper.listPadding(context),
        children: [
          // 유형 배지
          _TypeBadge(templateType: _templateType),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // 템플릿 이름
          _SectionHeader(label: '템플릿 이름'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _Card(
            child: TextField(
              controller: _nameCtrl,
              style: ResponsiveHelper.bodyStyle(context),
              decoration: InputDecoration(
                hintText: '예) 냉장분류 계약서, 일반 단기 계약서',
                hintStyle: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey400),
                border: InputBorder.none,
              ),
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // 고정 상단 안내
          _SectionHeader(label: '고정 상단 (자동 입력)'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Container(
            padding: EdgeInsets.all(
                ResponsiveHelper.spacing(context, 14)),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FixedRow('제1조 (근로계약 당사자)',
                    '사업장 정보 + 근로자 정보 자동 입력'),
                _FixedRow('제2조 (근무 조건)',
                    '공고 데이터 자동 입력'),
                _FixedRow('제3조 (임금)',
                    '업무상세 임금 정보 자동 입력'),
              ],
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // 편집 가능 조항
          Row(
            children: [
              Expanded(
                child: _SectionHeader(label: '편집 가능 조항'),
              ),
              Text(
                '드래그로 순서 변경',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey400),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),

          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _entries.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _entries.removeAt(oldIndex);
                _entries.insert(newIndex, item);
              });
            },
            itemBuilder: (ctx, i) {
              final entry = _entries[i];
              return _ArticleCard(
                key: ValueKey(entry),
                index: i,
                entry: entry,
                onDelete: () => _removeArticle(i),
              );
            },
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 조항 추가 버튼
          OutlinedButton.icon(
            onPressed: _addArticle,
            icon: const Icon(Icons.add),
            label: const Text('조항 추가'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primaryColor,
              side: BorderSide(color: theme.primaryColor),
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 14)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),

          // AppPageScaffold는 body에 하단 SafeArea를 적용하지 않는다.
          // 시각적 여백(32) + 기기 하단 인셋(홈 인디케이터/제스처 바)을 더해
          // 마지막 조항/추가 버튼이 시스템 내비게이션 영역에 가려지지 않도록 한다.
          SizedBox(
            height: ResponsiveHelper.spacing(context, 32) +
                MediaQuery.paddingOf(context).bottom,
          ),
        ],
      ),
    ),
  );
  }
}

// ─── 조항 편집 카드 ───────────────────────────────────────────────

class _ArticleEntry {
  final TextEditingController titleCtrl;
  final TextEditingController contentCtrl;
  _ArticleEntry({required this.titleCtrl, required this.contentCtrl});
}

class _ArticleCard extends StatelessWidget {
  final int index;
  final _ArticleEntry entry;
  final VoidCallback onDelete;

  const _ArticleCard({
    super.key,
    required this.index,
    required this.entry,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
          bottom: ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 카드 헤더 (번호 + 드래그 핸들 + 삭제)
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 6),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .primaryColor
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: ResponsiveHelper.tinyStyle(context,
                              color: Theme.of(context).primaryColor)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: TextField(
                    controller: entry.titleCtrl,
                    style: ResponsiveHelper.smallStyle(context)
                        .copyWith(fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: '조항 제목 (예: 제4조 (연장·야간근로 수당))',
                      hintStyle: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey400),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Icon(Icons.drag_handle,
                      color: AppColors.grey400,
                      size: ResponsiveHelper.iconSize(context, 20)),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Semantics(
                  button: true,
                  label: '문단 삭제',
                  child: GestureDetector(
                    onTap: onDelete,
                    child: Icon(Icons.close,
                        color: AppColors.grey400,
                        size: ResponsiveHelper.iconSize(context, 18)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.grey100),
          // 내용
          Padding(
            padding: EdgeInsets.all(
                ResponsiveHelper.spacing(context, 12)),
            child: TextField(
              controller: entry.contentCtrl,
              style: ResponsiveHelper.smallStyle(context),
              decoration: InputDecoration(
                hintText: '조항 내용을 자유롭게 작성하세요',
                hintStyle: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey400),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              maxLines: null,
              keyboardType: TextInputType.multiline,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 유형 배지 ───────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String templateType;
  const _TypeBadge({required this.templateType});

  @override
  Widget build(BuildContext context) {
    Color color;
    Color bg;
    String icon;
    switch (templateType) {
      case ContractTemplateType.daily:
        color = AppColors.info;
        bg    = AppColors.infoBg;
        icon  = '📋';
        break;
      case ContractTemplateType.period:
        color = AppColors.success;
        bg    = AppColors.successBg;
        icon  = '📄';
        break;
      case ContractTemplateType.outsource:
        color = AppColors.warning;
        bg    = AppColors.warningBg;
        icon  = '📃';
        break;
      default:
        color = AppColors.grey600;
        bg    = AppColors.grey100;
        icon  = '📋';
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: TextStyle(fontSize: ResponsiveHelper.iconSize(context, 16))),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ContractTemplateType.label(templateType),
                style: ResponsiveHelper.smallStyle(context)
                    .copyWith(color: color, fontWeight: FontWeight.w700),
              ),
              Text(
                ContractTemplateType.description(templateType),
                style: ResponsiveHelper.tinyStyle(context,
                    color: color.withValues(alpha: 0.8)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 공통 서브위젯 ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: ResponsiveHelper.smallStyle(context,
              color: AppColors.grey600)
          .copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.grey200),
      ),
      child: child,
    );
  }
}

class _FixedRow extends StatelessWidget {
  final String title;
  final String description;
  const _FixedRow(this.title, this.description);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: ResponsiveHelper.spacing(context, 6)),
      child: Row(
        children: [
          Icon(Icons.lock_outline,
              size: ResponsiveHelper.iconSize(context, 14),
              color: AppColors.grey400),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text(title,
              style: ResponsiveHelper.smallStyle(context)
                  .copyWith(fontWeight: FontWeight.w500)),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(description,
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey400)),
          ),
        ],
      ),
    );
  }
}
