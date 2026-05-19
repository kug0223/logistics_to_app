import 'package:flutter/material.dart';
import '../../models/core/business_work_type_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import 'icon_picker_dialog.dart';

/// 업무유형 추가/수정 바텀시트
class AddWorkTypeSheet extends StatefulWidget {
  final BusinessWorkTypeModel? editTarget;

  const AddWorkTypeSheet._({this.editTarget});

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    BusinessWorkTypeModel? editTarget,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddWorkTypeSheet._(editTarget: editTarget),
    );
  }

  @override
  State<AddWorkTypeSheet> createState() => _AddWorkTypeSheetState();
}

class _AddWorkTypeSheetState extends State<AddWorkTypeSheet> {
  static const List<Color> _palette = [
    Color(0xFF1565C0),
    Color(0xFF00897B),
    Color(0xFF2E7D32),
    Color(0xFFF57F17),
    Color(0xFFE53935),
    Color(0xFF6A1B9A),
    Color(0xFF37474F),
    Color(0xFFD81B60),
  ];

  static String _toHex(Color c) {
    final rgb = c.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  late Color _bgColor;
  IconItem? _selectedIcon;
  List<IconItem> _suggested = [];

  bool get _isEdit => widget.editTarget != null;

  @override
  void initState() {
    super.initState();
    _bgColor = _palette[0];

    final edit = widget.editTarget;
    if (edit != null) {
      _nameCtrl.text = edit.name;
      _searchCtrl.text = edit.name;

      if (edit.backgroundColor != null) {
        try {
          _bgColor = FormatHelper.parseColor(edit.backgroundColor!);
        } catch (_) {}
      }

      if (edit.icon.startsWith('material:')) {
        final cp = int.tryParse(edit.icon.substring(9));
        if (cp != null) {
          final all = IconPickerDialog.getAllIcons();
          try {
            _selectedIcon = all.firstWhere((i) => i.icon.codePoint == cp);
          } catch (_) {
            _selectedIcon = IconItem(
              icon: IconData(cp, fontFamily: 'MaterialIcons'),
              label: '',
              keywords: [],
              category: '',
            );
          }
        }
      }
    }

    _suggested = IconPickerDialog.getSuggestedIcons(_searchCtrl.text);
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final newSuggested = IconPickerDialog.getSuggestedIcons(_searchCtrl.text);
    setState(() {
      _suggested = newSuggested;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openFullPicker() async {
    final result = await IconPickerDialog.show(
      context: context,
      initialSearchText: _searchCtrl.text,
      initialIcon: _selectedIcon != null
          ? 'material:${_selectedIcon!.icon.codePoint}'
          : null,
    );
    if (result != null && mounted) {
      setState(() => _selectedIcon = result);
    }
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final iconStr = _selectedIcon != null
        ? 'material:${_selectedIcon!.icon.codePoint}'
        : null;

    Navigator.pop(context, {
      'name': name,
      'icon': iconStr,
      'iconColor': '#FFFFFF',
      'backgroundColor': _toHex(_bgColor),
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          _header(),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 20),
                0,
                ResponsiveHelper.spacing(context, 20),
                ResponsiveHelper.spacing(context, 20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  _preview(),
                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                  _iconSearchField(theme),
                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                  _iconRow(theme),
                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                  _colorRow(theme),
                  SizedBox(height: ResponsiveHelper.spacing(context, 32)),
                  _actions(theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _handle() => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.grey300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header() => Padding(
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 4),
          ResponsiveHelper.spacing(context, 8),
          0,
        ),
        child: Row(
          children: [
            Text(
              _isEdit ? '업무유형 수정' : '새 업무유형 추가',
              style: ResponsiveHelper.titleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );

  // ─── 미리보기 + 이름 직접 입력 ────────────────────────────────────
  Widget _preview() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _bgColor.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // 왼쪽 아이콘 (고정 너비)
          SizedBox(
            width: 30,
            child: _buildPreviewIcon(),
          ),
          // 가운데 이름 입력 (Expanded + 텍스트 가운데 정렬)
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              autofocus: !_isEdit,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                hintText: '업무유형 이름 입력',
                hintStyle: TextStyle(color: Colors.white54, fontSize: 15),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              cursorColor: Colors.white,
              textInputAction: TextInputAction.done,
            ),
          ),
          // 오른쪽 균형용 공간 (왼쪽 아이콘과 동일 너비)
          const SizedBox(width: 30),
        ],
      ),
    );
  }

  Widget _buildPreviewIcon() {
    if (_selectedIcon != null) {
      return Icon(_selectedIcon!.icon, color: Colors.white, size: 22);
    }
    return ListenableBuilder(
      listenable: _nameCtrl,
      builder: (_, __) {
        if (_nameCtrl.text.isNotEmpty) {
          return Text(
            _nameCtrl.text.characters.first,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          );
        }
        return const Icon(Icons.edit, color: Colors.white54, size: 20);
      },
    );
  }

  // ─── 아이콘 검색 필드 ─────────────────────────────────────────────
  Widget _iconSearchField(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('아이콘 검색'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '예: 배달, 청소, 요리, 운동',
              prefixIcon:
                  Icon(Icons.search, color: theme.primaryColor),
              suffixIcon: ListenableBuilder(
                listenable: _searchCtrl,
                builder: (_, __) => _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            textInputAction: TextInputAction.search,
          ),
        ],
      );

  // ─── 아이콘 추천 행 ───────────────────────────────────────────────
  Widget _iconRow(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _label('아이콘'),
              const Spacer(),
              TextButton.icon(
                onPressed: _openFullPicker,
                icon: Icon(Icons.grid_view_rounded,
                    size: 15, color: theme.primaryColor),
                label: Text(
                  '전체 보기',
                  style: TextStyle(
                      fontSize: 12, color: theme.primaryColor),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _iconChip(null, isNone: true, theme: theme),
                const SizedBox(width: 8),
                if (_selectedIcon != null &&
                    !_suggested.any(
                        (s) => s.icon.codePoint == _selectedIcon!.icon.codePoint)) ...[
                  _iconChip(_selectedIcon, theme: theme),
                  const SizedBox(width: 8),
                ],
                ..._suggested.map((item) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _iconChip(item, theme: theme),
                    )),
              ],
            ),
          ),
        ],
      );

  Widget _iconChip(IconItem? item,
      {bool isNone = false, required ThemeData theme}) {
    final isSelected = isNone
        ? _selectedIcon == null
        : item != null &&
            _selectedIcon?.icon.codePoint == item.icon.codePoint;

    return GestureDetector(
      onTap: () => setState(() => _selectedIcon = isNone ? null : item),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isSelected ? _bgColor : AppColors.grey100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? _bgColor : AppColors.grey200,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: _bgColor.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isNone ? Icons.do_not_disturb_alt_outlined : item!.icon,
              color: isSelected ? Colors.white : AppColors.grey500,
              size: 26,
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 52,
            child: Text(
              isNone ? '없음' : (item!.label),
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? theme.primaryColor : AppColors.grey500,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 배경색 선택 ──────────────────────────────────────────────────
  Widget _colorRow(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('배경색'),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: _palette.map((color) {
              final isSelected =
                  _bgColor.toARGB32() == color.toARGB32();
              return GestureDetector(
                onTap: () => setState(() => _bgColor = color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: isSelected ? 42 : 36,
                  height: isSelected ? 42 : 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 18)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      );

  // ─── 액션 버튼 ────────────────────────────────────────────────────
  Widget _actions(ThemeData theme) => Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('취소'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ListenableBuilder(
              listenable: _nameCtrl,
              builder: (_, __) => ElevatedButton(
                onPressed:
                    _nameCtrl.text.trim().isEmpty ? null : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_isEdit ? '수정 완료' : '추가'),
              ),
            ),
          ),
        ],
      );

  Widget _label(String text) => Text(
        text,
        style: ResponsiveHelper.smallStyle(context).copyWith(
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary,
        ),
      );
}
