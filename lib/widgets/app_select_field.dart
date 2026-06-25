import 'dart:math' show max;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/responsive_helper.dart';

/// 공통 선택 필드 — 탭하면 바텀시트 목록이 열림
///
/// DropdownButtonFormField / DropdownButton 대체 위젯.
/// items가 8개 초과이면 검색창이 자동으로 표시됩니다.
///
/// ```dart
/// AppSelectField<String>(
///   value: selectedBank,
///   hintText: '은행 선택',
///   sheetTitle: '은행 선택',
///   items: bankList,
///   labelOf: (b) => b,
///   onChanged: (b) => setState(() => selectedBank = b),
/// )
/// ```
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    super.key,
    this.value,
    required this.hintText,
    required this.sheetTitle,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.leadingOf,
    this.enabled = true,
    this.prefixIcon,
    this.showSearch,
  });

  /// 현재 선택값 (null = 미선택)
  final T? value;

  /// 미선택 시 표시할 힌트 텍스트
  final String hintText;

  /// 바텀시트 헤더 제목
  final String sheetTitle;

  /// 선택 목록
  final List<T> items;

  /// 선택값 → 표시 텍스트
  final String Function(T item) labelOf;

  /// 목록 아이템 앞에 표시할 위젯 (아이콘·색상 뱃지 등, 선택사항)
  final Widget Function(T item)? leadingOf;

  /// 변경 콜백
  final ValueChanged<T?> onChanged;

  /// 비활성화 여부
  final bool enabled;

  /// 트리거 타일 왼쪽 아이콘 (선택사항)
  final IconData? prefixIcon;

  /// 검색창 표시 여부 (null = 8개 초과 시 자동, false = 항상 숨김, true = 항상 표시)
  final bool? showSearch;

  Future<void> _openSheet(BuildContext context) async {
    final theme = Theme.of(context);
    final result = await showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AppSelectSheet<T>(
        title: sheetTitle,
        items: items,
        selected: value,
        labelOf: labelOf,
        leadingOf: leadingOf,
        theme: theme,
        showSearch: showSearch,
      ),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value != null;

    return Material(
      color: AppColors.grey50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? () => _openSheet(context) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
            vertical: ResponsiveHelper.spacing(context, 14),
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasValue ? theme.primaryColor : AppColors.grey300,
              width: hasValue ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              if (prefixIcon != null) ...[
                Icon(
                  prefixIcon,
                  color: hasValue ? theme.primaryColor : AppColors.grey400,
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              ],
              if (hasValue && leadingOf != null) ...[
                leadingOf!(value as T),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              ],
              Expanded(
                child: Text(
                  hasValue ? labelOf(value as T) : hintText,
                  style: hasValue
                      ? ResponsiveHelper.bodyStyle(context)
                          .copyWith(fontWeight: FontWeight.w600)
                      : ResponsiveHelper.bodyStyle(context)
                          .copyWith(color: AppColors.grey400),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.expand_more,
                color: hasValue ? theme.primaryColor : AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 바텀시트 내부 위젯
// ──────────────────────────────────────────────────────────────

class _AppSelectSheet<T> extends StatefulWidget {
  const _AppSelectSheet({
    required this.title,
    required this.items,
    required this.selected,
    required this.labelOf,
    required this.theme,
    this.leadingOf,
    this.showSearch,
  });

  final String title;
  final List<T> items;
  final T? selected;
  final String Function(T) labelOf;
  final Widget Function(T)? leadingOf;
  final ThemeData theme;
  final bool? showSearch;

  @override
  State<_AppSelectSheet<T>> createState() => _AppSelectSheetState<T>();
}

class _AppSelectSheetState<T> extends State<_AppSelectSheet<T>> {
  late List<T> _filtered;
  final _searchController = TextEditingController();

  bool get _showSearch => widget.showSearch ?? widget.items.length > 8;

  @override
  void initState() {
    super.initState();
    _filtered = List.from(widget.items);
    _searchController.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchController.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List.from(widget.items)
          : widget.items
              .where((item) =>
                  widget.labelOf(item).toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들바
          Container(
            margin: EdgeInsets.only(
              top: ResponsiveHelper.spacing(context, 12),
              bottom: ResponsiveHelper.spacing(context, 4),
            ),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 제목 + 닫기
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 20),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                  color: AppColors.grey600,
                ),
              ],
            ),
          ),

          // 검색창 (8개 초과 시 자동 표시)
          if (_showSearch)
            Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 16),
                0,
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 8),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '검색',
                  hintStyle: ResponsiveHelper.bodyStyle(context,
                      color: AppColors.grey400),
                  prefixIcon: Icon(Icons.search,
                      size: ResponsiveHelper.iconSize(context, 20),
                      color: AppColors.grey400),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  filled: true,
                  fillColor: AppColors.grey100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

          const Divider(height: 1, color: AppColors.grey200),

          // 목록
          Flexible(
            child: _filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      '검색 결과가 없습니다',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.grey400),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.grey100),
                    itemBuilder: (context, index) {
                      final item = _filtered[index];
                      final isSelected = item == widget.selected;
                      return InkWell(
                        onTap: () => Navigator.pop(context, item),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 16),
                            vertical: ResponsiveHelper.spacing(context, 13),
                          ),
                          child: Row(
                            children: [
                              if (widget.leadingOf != null) ...[
                                widget.leadingOf!(item),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Text(
                                  widget.labelOf(item),
                                  style: ResponsiveHelper.bodyStyle(
                                    context,
                                    color: isSelected
                                        ? widget.theme.primaryColor
                                        : AppColors.textPrimary,
                                  ).copyWith(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check,
                                    color: widget.theme.primaryColor,
                                    size: ResponsiveHelper.iconSize(context, 20)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // edge-to-edge 대응: viewPaddingOf는 SafeArea 소비 무관 물리적 인셋.
          // max로 SafeArea 정상 동작 시 이중 합산 방지.
          SizedBox(height: max(8.0, MediaQuery.viewPaddingOf(context).bottom)),
        ],
      ),
    );
  }
}
