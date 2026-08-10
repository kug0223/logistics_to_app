// lib/screens/super_admin/help_faq_management_screen.dart
//
// 슈퍼관리자 도움말 FAQ 관리 화면
// - 지원자/관리자 탭 분리
// - 항목 추가·수정·삭제·활성화·순서 변경

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/core/help_faq_model.dart';
import '../../providers/user_provider.dart';
import '../../services/help_faq_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';

class HelpFaqManagementScreen extends StatefulWidget {
  const HelpFaqManagementScreen({super.key});

  @override
  State<HelpFaqManagementScreen> createState() =>
      _HelpFaqManagementScreenState();
}

class _HelpFaqManagementScreenState extends State<HelpFaqManagementScreen>
    with SingleTickerProviderStateMixin {
  final _service = HelpFaqService();
  late TabController _tabController;

  List<HelpFaqModel> _userItems = [];
  List<HelpFaqModel> _adminItems = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final results = await Future.wait([
        _service.getAllItems('user'),
        _service.getAllItems('admin'),
      ]);
      if (!mounted) return;
      setState(() {
        _userItems = results[0];
        _adminItems = results[1];
      });
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
      if (mounted) ToastHelper.showError('FAQ를 불러오는데 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _seedDefaults() async {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '기본값으로 초기화',
      message: '현재 FAQ 전체가 기본값으로 교체됩니다.\n이 작업은 되돌릴 수 없습니다.',
      confirmText: '초기화',
      confirmColor: AppColors.errorDark,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _service.seedDefaults();
      if (!mounted) return;
      ToastHelper.showSuccess('기본값으로 초기화되었습니다');
      await _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('초기화에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _addItem(String role) async {
    final result = await _showEditSheet(
      context,
      role: role,
      item: null,
      existingCategories: _categoriesFor(role),
    );
    if (result == null || !mounted) return;
    setState(() => _isSaving = true);
    try {
      final order = role == 'user' ? _userItems.length : _adminItems.length;
      await _service.addItem(result.copyWith(order: order));
      if (!mounted) return;
      ToastHelper.showSuccess('항목이 추가되었습니다');
      await _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('추가에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editItem(HelpFaqModel item) async {
    final result = await _showEditSheet(
      context,
      role: item.role,
      item: item,
      existingCategories: _categoriesFor(item.role),
    );
    if (result == null || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await _service.updateItem(result);
      if (!mounted) return;
      ToastHelper.showSuccess('저장되었습니다');
      await _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('저장에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteItem(HelpFaqModel item) async {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '항목 삭제',
      message: '"${item.isHeader ? item.category : item.question}"을(를) 삭제할까요?',
      confirmText: '삭제',
      confirmColor: AppColors.errorDark,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await _service.deleteItem(item.id);
      if (!mounted) return;
      ToastHelper.showSuccess('삭제되었습니다');
      await _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('삭제에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _toggleActive(HelpFaqModel item) async {
    // 재진입 방어: 연속 탭 시 updateItem 병렬 실행 → 최종 상태 비결정적 방지
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _service.updateItem(item.copyWith(isActive: !item.isActive));
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('변경에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _reorder(String role, int oldIndex, int newIndex) async {
    if (_isSaving) return; // _toggleActive / _delete 진행 중 재진입 방지
    final items = role == 'user' ? _userItems : _adminItems;
    final original = List<HelpFaqModel>.from(items);
    if (newIndex > oldIndex) newIndex--;
    final updated = List<HelpFaqModel>.from(items);
    final moved = updated.removeAt(oldIndex);
    updated.insert(newIndex, moved);
    // 즉시 UI 반영
    setState(() {
      if (role == 'user') {
        _userItems = updated;
      } else {
        _adminItems = updated;
      }
    });
    try {
      await _service.reorderItems(updated);
    } catch (e) {
      if (mounted) {
        setState(() {
          if (role == 'user') {
            _userItems = original;
          } else {
            _adminItems = original;
          }
        });
        ToastHelper.showError('순서 저장에 실패했습니다');
      }
    }
  }

  List<String> _categoriesFor(String role) {
    final items = role == 'user' ? _userItems : _adminItems;
    return items
        .where((i) => i.isHeader)
        .map((i) => i.category)
        .toSet()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '도움말 FAQ 관리',
      actions: [
        if (_isSaving)
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.restore, color: Colors.white),
            tooltip: '기본값으로 초기화',
            onPressed: _seedDefaults,
          ),
      ],
      headerBottom: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        tabs: const [
          Tab(text: '지원자 FAQ'),
          Tab(text: '관리자 FAQ'),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : _hasError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                      const SizedBox(height: 12),
                      Text('FAQ를 불러오지 못했습니다',
                          style: ResponsiveHelper.bodyStyle(context)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _load,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
              controller: _tabController,
              children: [
                _FaqList(
                  role: 'user',
                  items: _userItems,
                  theme: theme,
                  onAdd: () => _addItem('user'),
                  onEdit: _editItem,
                  onDelete: _deleteItem,
                  onToggle: _toggleActive,
                  onReorder: (o, n) => _reorder('user', o, n),
                ),
                _FaqList(
                  role: 'admin',
                  items: _adminItems,
                  theme: theme,
                  onAdd: () => _addItem('admin'),
                  onEdit: _editItem,
                  onDelete: _deleteItem,
                  onToggle: _toggleActive,
                  onReorder: (o, n) => _reorder('admin', o, n),
                ),
              ],
            ),
    );
  }
}

// ──────────────────────────────────────────────
// FAQ 목록 위젯
// ──────────────────────────────────────────────
class _FaqList extends StatelessWidget {
  final String role;
  final List<HelpFaqModel> items;
  final ThemeData theme;
  final VoidCallback onAdd;
  final Future<void> Function(HelpFaqModel) onEdit;
  final Future<void> Function(HelpFaqModel) onDelete;
  final Future<void> Function(HelpFaqModel) onToggle;
  final Future<void> Function(int, int) onReorder;

  const _FaqList({
    required this.role,
    required this.items,
    required this.theme,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final sp = ResponsiveHelper.spacing(context, 1);
    return Stack(
      children: [
        ReorderableListView.builder(
          padding:
              EdgeInsets.fromLTRB(sp * 16, sp * 8, sp * 16, sp * 80),
          itemCount: items.length,
          onReorder: onReorder,
          itemBuilder: (context, i) {
            final item = items[i];
            return _FaqRowItem(
              key: ValueKey(item.id.isEmpty ? '${item.role}_$i' : item.id),
              item: item,
              theme: theme,
              onEdit: () => onEdit(item),
              onDelete: () => onDelete(item),
              onToggle: () => onToggle(item),
            );
          },
        ),
        Positioned(
          bottom: sp * 16,
          right: sp * 16,
          child: FloatingActionButton.extended(
            heroTag: 'fab_$role',
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('항목 추가'),
            backgroundColor: theme.primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _FaqRowItem extends StatelessWidget {
  final HelpFaqModel item;
  final ThemeData theme;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _FaqRowItem({
    super.key,
    required this.item,
    required this.theme,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final sp = ResponsiveHelper.spacing(context, 1);
    final isHeader = item.isHeader;
    return Container(
      margin: EdgeInsets.only(bottom: sp * 6),
      decoration: BoxDecoration(
        color: isHeader
            ? theme.primaryColor.withValues(alpha: 0.06)
            : (item.isActive ? Colors.white : AppColors.grey50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHeader
              ? theme.primaryColor.withValues(alpha: 0.2)
              : AppColors.grey200,
        ),
      ),
      child: ListTile(
        contentPadding:
            EdgeInsets.symmetric(horizontal: sp * 14, vertical: sp * 2),
        leading: isHeader
            ? Icon(Icons.label_outline,
                color: theme.primaryColor, size: sp * 20)
            : Icon(
                item.isActive
                    ? Icons.help_outline_rounded
                    : Icons.visibility_off_outlined,
                color: item.isActive ? AppColors.grey600 : AppColors.grey400,
                size: sp * 18,
              ),
        title: Text(
          isHeader ? item.category : item.question,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
            color: item.isActive ? null : AppColors.grey400,
          ),
        ),
        subtitle: isHeader
            ? Text(
                '카테고리 헤더',
                style: ResponsiveHelper.smallStyle(context,
                    color: theme.primaryColor),
              )
            : item.answer.isNotEmpty
                ? Text(
                    item.answer,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey500),
                  )
                : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                item.isActive
                    ? Icons.toggle_on_rounded
                    : Icons.toggle_off_rounded,
                color: item.isActive ? theme.primaryColor : AppColors.grey400,
                size: 28,
              ),
              onPressed: onToggle,
              tooltip: item.isActive ? '비활성화' : '활성화',
            ),
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.grey600),
              onPressed: onEdit,
              tooltip: '수정',
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18, color: AppColors.errorDark),
              onPressed: onDelete,
              tooltip: '삭제',
            ),
            Icon(Icons.drag_handle, color: AppColors.grey400, size: 20),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// FAQ 편집 바텀시트
// ──────────────────────────────────────────────
Future<HelpFaqModel?> _showEditSheet(
  BuildContext context, {
  required String role,
  required HelpFaqModel? item,
  required List<String> existingCategories,
}) {
  return DialogHelper.showSheet<HelpFaqModel>(
    context,
    isScrollControlled: true,
    builder: (ctx) => _EditSheet(
      role: role,
      item: item,
      existingCategories: existingCategories,
    ),
  );
}

class _EditSheet extends StatefulWidget {
  final String role;
  final HelpFaqModel? item;
  final List<String> existingCategories;

  const _EditSheet({
    required this.role,
    required this.item,
    required this.existingCategories,
  });

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _questionCtrl;
  late final TextEditingController _answerCtrl;
  bool _isHeader = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _isHeader = item?.isHeader ?? false;
    _categoryCtrl =
        TextEditingController(text: item?.category ?? '');
    _questionCtrl =
        TextEditingController(text: item != null && !item.isHeader ? item.question : '');
    _answerCtrl = TextEditingController(text: item?.answer ?? '');
  }

  @override
  void dispose() {
    _categoryCtrl.dispose();
    _questionCtrl.dispose();
    _answerCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final category = _categoryCtrl.text.trim();
    if (category.isEmpty) {
      ToastHelper.showError('카테고리를 입력해주세요');
      return;
    }
    if (!_isHeader && _questionCtrl.text.trim().isEmpty) {
      ToastHelper.showError('질문을 입력해주세요');
      return;
    }
    if (!_isHeader && _answerCtrl.text.trim().isEmpty) {
      ToastHelper.showError('답변을 입력해주세요');
      return;
    }
    final item = widget.item;
    final result = HelpFaqModel(
      id: item?.id ?? '',
      role: widget.role,
      order: item?.order ?? 0,
      category: category,
      question: _isHeader ? category : _questionCtrl.text.trim(),
      answer: _isHeader ? '' : _answerCtrl.text.trim(),
      isHeader: _isHeader,
      isActive: item?.isActive ?? true,
    );
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sp = ResponsiveHelper.spacing(context, 1);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          Center(
            child: Container(
              margin: EdgeInsets.only(top: sp * 12, bottom: sp * 4),
              width: sp * 40,
              height: sp * 4,
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: sp * 20, vertical: sp * 4),
            child: Text(
              widget.item == null ? 'FAQ 항목 추가' : 'FAQ 항목 수정',
              style: ResponsiveHelper.titleStyle(context),
            ),
          ),
          const Divider(height: 1),
          SingleChildScrollView(
            padding: EdgeInsets.all(sp * 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더 여부 스위치
                Row(
                  children: [
                    Icon(Icons.label_outline,
                        size: sp * 18, color: theme.primaryColor),
                    SizedBox(width: sp * 8),
                    Text('카테고리 헤더',
                        style: ResponsiveHelper.bodyStyle(context)),
                    const Spacer(),
                    Switch(
                      value: _isHeader,
                      onChanged: (v) => setState(() => _isHeader = v),
                      activeThumbColor: theme.primaryColor,
                    ),
                  ],
                ),
                SizedBox(height: sp * 16),
                // 카테고리
                Text('카테고리',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey600,
                        fontWeight: FontWeight.w600)),
                SizedBox(height: sp * 6),
                // 기존 카테고리 선택
                if (widget.existingCategories.isNotEmpty) ...[
                  Wrap(
                    spacing: sp * 6,
                    runSpacing: sp * 6,
                    children: widget.existingCategories.map((cat) {
                      final selected =
                          _categoryCtrl.text == cat;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _categoryCtrl.text = cat),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: sp * 10, vertical: sp * 6),
                          decoration: BoxDecoration(
                            color: selected
                                ? theme.primaryColor
                                : AppColors.grey100,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            cat,
                            style: ResponsiveHelper.smallStyle(context,
                                color: selected
                                    ? Colors.white
                                    : AppColors.grey700),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  SizedBox(height: sp * 8),
                ],
                TextField(
                  controller: _categoryCtrl,
                  decoration: InputDecoration(
                    hintText: '예) 📋 공고 & 지원',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: EdgeInsets.all(sp * 12),
                  ),
                  style: ResponsiveHelper.bodyStyle(context),
                  onChanged: (_) => setState(() {}),
                ),
                // 질문/답변 (헤더가 아닐 때만)
                if (!_isHeader) ...[
                  SizedBox(height: sp * 16),
                  Text('질문',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: sp * 6),
                  TextField(
                    controller: _questionCtrl,
                    decoration: InputDecoration(
                      hintText: '예) 공고에 어떻게 지원하나요?',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: EdgeInsets.all(sp * 12),
                    ),
                    style: ResponsiveHelper.bodyStyle(context),
                  ),
                  SizedBox(height: sp * 16),
                  Text('답변',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600,
                          fontWeight: FontWeight.w600)),
                  SizedBox(height: sp * 6),
                  TextField(
                    controller: _answerCtrl,
                    decoration: InputDecoration(
                      hintText: '상세 설명을 입력하세요',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: EdgeInsets.all(sp * 12),
                    ),
                    style: ResponsiveHelper.bodyStyle(context),
                    maxLines: 5,
                    minLines: 3,
                  ),
                ],
                SizedBox(height: sp * 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: sp * 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(
                      widget.item == null ? '추가' : '저장',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: Colors.white,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
