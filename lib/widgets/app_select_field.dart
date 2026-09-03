import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/dialog_helper.dart';
import '../utils/responsive_helper.dart';

// ──────────────────────────────────────────────────────────────
// 그룹 구조 정의
// ──────────────────────────────────────────────────────────────

/// 선택 목록을 논리적 그룹으로 묶을 때 사용
class AppSelectGroup<T> {
  final String header;
  final List<T> items;
  const AppSelectGroup({required this.header, required this.items});
}

// ──────────────────────────────────────────────────────────────
// 트리거 필드
// ──────────────────────────────────────────────────────────────

/// 공통 선택 필드 — 탭하면 바텀시트 목록이 열림
///
/// [groups]를 제공하면 바텀시트에서 카테고리 헤더가 표시됩니다.
class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    super.key,
    this.value,
    required this.hintText,
    required this.sheetTitle,
    this.items = const [],
    required this.labelOf,
    required this.onChanged,
    this.groups,
    this.searchHint,
    this.leadingOf,
    this.enabled = true,
    this.prefixIcon,
    this.showSearch,
    this.useRootNavigator = false,
  });

  final T? value;
  final String hintText;
  final String sheetTitle;

  /// 선택 목록 (groups 미사용 시)
  final List<T> items;

  /// 그룹화된 선택 목록 — 제공 시 바텀시트에서 카테고리 헤더 표시
  final List<AppSelectGroup<T>>? groups;

  /// 검색창 힌트 텍스트 (기본값: '검색')
  final String? searchHint;

  final String Function(T item) labelOf;
  final Widget Function(T item)? leadingOf;
  final ValueChanged<T?> onChanged;
  final bool enabled;
  final IconData? prefixIcon;

  /// 검색창 표시 여부 (null = 8개 초과 시 자동, false = 항상 숨김, true = 항상 표시)
  final bool? showSearch;

  /// Dialog 안에서 사용할 때 true로 설정 — 루트 Navigator로 시트를 표시해
  /// Dialog의 Focus/Overlay 스택과 충돌하는 RenderErrorBox 크래시를 방지한다.
  final bool useRootNavigator;

  List<T> get _allItems =>
      groups != null ? groups!.expand((g) => g.items).toList() : items;

  Future<void> _openSheet(BuildContext context) async {
    final theme = Theme.of(context);
    final result = await DialogHelper.showSheet<T>(
      context,
      isScrollControlled: true,
      useRootNavigator: useRootNavigator,
      builder: (ctx) => _AppSelectSheet<T>(
        title: sheetTitle,
        items: _allItems,
        groups: groups,
        selected: value,
        labelOf: labelOf,
        leadingOf: leadingOf,
        primaryColor: theme.primaryColor,
        showSearch: showSearch,
        searchHint: searchHint,
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
    required this.primaryColor,
    this.groups,
    this.leadingOf,
    this.showSearch,
    this.searchHint,
  });

  final String title;
  final List<T> items;
  final List<AppSelectGroup<T>>? groups;
  final T? selected;
  final String Function(T) labelOf;
  final Widget Function(T)? leadingOf;
  final Color primaryColor;
  final bool? showSearch;
  final String? searchHint;

  @override
  State<_AppSelectSheet<T>> createState() => _AppSelectSheetState<T>();
}

class _AppSelectSheetState<T> extends State<_AppSelectSheet<T>> {
  late List<T> _filtered;
  final _searchCtrl = TextEditingController();

  bool get _showSearch => widget.showSearch ?? widget.items.length > 8;

  @override
  void initState() {
    super.initState();
    _filtered = List.from(widget.items);
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? List.from(widget.items)
          : widget.items
              .where((i) => widget.labelOf(i).toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // 레이아웃 수치 상수 (명세 기준)
  // ─────────────────────────────────────────────────────────

  // Row 높이: 52dp 고정 (내부 vertical padding 없음)
  static const double _kRowHeight = 52;

  // 좌우 공통 padding: 24dp
  static const double _kHPad = 24;

  // Section title typography
  static const double _kSectionFontSize = 13;

  // 은행명 typography
  static const double _kBankFontSize = 16;

  // Row 간 구분선 색상
  static const Color _kDividerColor = Color(0xFFEEEEEE);

  // ─────────────────────────────────────────────────────────
  // build
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 드래그 핸들 ──────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── 제목 + 닫기 ──────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.grey900,
                    ),
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

          // ── 검색창 ───────────────────────────────────
          // height ≈ 52dp: contentPadding(vertical:15*2=30) + fontSize15 기준 lineHeight ≈ 22 → 합계 약 52
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontSize: 15, color: AppColors.grey900),
                decoration: InputDecoration(
                  hintText: widget.searchHint ?? '검색',
                  hintStyle: const TextStyle(
                      fontSize: 15, color: Color(0xFF9E9E9E)),
                  prefixIcon: const Icon(Icons.search,
                      size: 20, color: Color(0xFF9E9E9E)),
                  // height ≈ 52dp
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                  filled: true,
                  fillColor: const Color(0xFFF7F8FA),
                  // border 없음
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                        color: widget.primaryColor.withValues(alpha: 0.35),
                        width: 1.5),
                  ),
                ),
              ),
            ),

          // 검색창과 목록 사이 구분선
          Container(height: 1, color: AppColors.grey200),

          // ── 목록 ─────────────────────────────────────
          Flexible(
            child: widget.groups != null
                ? _buildGroupedList(context)
                : _buildFlatList(context),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // 그룹 리스트
  // ─────────────────────────────────────────────────────────
  // 검색 시에도 그룹 구조 유지. 매칭 항목이 없는 그룹은 자동 숨김.

  Widget _buildGroupedList(BuildContext context) {
    final q = _searchCtrl.text.trim().toLowerCase();

    // 각 그룹 필터링 — 빈 그룹 제외
    final groups = widget.groups!
        .map((g) {
          final items = q.isEmpty
              ? g.items
              : g.items
                  .where((i) => widget.labelOf(i).toLowerCase().contains(q))
                  .toList();
          return _Grp<T>(g.header, items);
        })
        .where((g) => g.items.isNotEmpty)
        .toList();

    if (groups.isEmpty) {
      return _emptyResult(context);
    }

    // ── 위젯 리스트 조립 ────────────────────────────────
    // 구조: [section title] + [row, divider, row, ...] 반복
    // Row 높이: 56dp 고정 / 구분선: Container(height:1) / section gap: 24dp top

    final widgets = <Widget>[];

    for (var gi = 0; gi < groups.length; gi++) {
      final g = groups[gi];

      // 그룹 간 여백 (첫 번째 그룹 앞에는 없음)
      if (gi > 0) {
        widgets.add(const SizedBox(height: 16)); // 섹션 그룹 ↔ 섹션 그룹 간격
      }

      // 섹션 헤더 바 — 36dp 얇은 #F7F8FA 배경 띠
      // 헤더와 바로 아래 첫 번째 은행 Row는 붙어서 하나의 그룹처럼 보임
      widgets.add(
        Container(
          height: 36,
          color: const Color(0xFFF7F8FA),
          padding: const EdgeInsets.symmetric(horizontal: _kHPad),
          alignment: Alignment.centerLeft,
          child: Text(
            g.header,
            style: const TextStyle(
              fontSize: _kSectionFontSize,
              fontWeight: FontWeight.w600,
              color: Color(0xFF616161), // grey600
            ),
          ),
        ),
      );

      // 은행 Row 목록 — Row 사이에만 1dp 구분선 (#EEEEEE), 첫 번째 Row 앞에는 없음
      for (var ii = 0; ii < g.items.length; ii++) {
        if (ii > 0) {
          widgets.add(Container(height: 1, color: _kDividerColor));
        }
        widgets.add(_buildRow(context, g.items[ii]));
      }
    }

    // 하단 안전 여백
    widgets.add(const SizedBox(height: 8));

    return ListView(
      padding: EdgeInsets.zero,
      children: widgets,
    );
  }

  // ─────────────────────────────────────────────────────────
  // 단순 리스트 (groups 미사용)
  // ─────────────────────────────────────────────────────────

  Widget _buildFlatList(BuildContext context) {
    if (_filtered.isEmpty) return _emptyResult(context);

    final widgets = <Widget>[];
    for (var i = 0; i < _filtered.length; i++) {
      if (i > 0) widgets.add(Container(height: 1, color: _kDividerColor));
      widgets.add(_buildRow(context, _filtered[i]));
    }
    widgets.add(const SizedBox(height: 8));

    return ListView(padding: EdgeInsets.zero, children: widgets);
  }

  // ─────────────────────────────────────────────────────────
  // 은행 Row — 56dp 고정, 내부 vertical padding 없음
  // ─────────────────────────────────────────────────────────

  Widget _buildRow(BuildContext context, T item) {
    final isSelected = item == widget.selected;

    return InkWell(
      onTap: () => Navigator.pop(context, item),
      child: SizedBox(
        height: _kRowHeight, // ← 56dp 고정
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _kHPad),
          // vertical padding 없음 — SizedBox가 높이를 결정
          child: Row(
            children: [
              if (widget.leadingOf != null) ...[
                widget.leadingOf!(item),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  widget.labelOf(item),
                  style: TextStyle(
                    fontSize: _kBankFontSize,
                    fontWeight: FontWeight.w400, // 400 (Regular)
                    color: isSelected
                        ? widget.primaryColor
                        : AppColors.grey900, // #212121
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 선택된 항목만 체크 표시 — chevron 없음
              if (isSelected)
                Icon(Icons.check_rounded,
                    color: widget.primaryColor, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // 빈 결과
  // ─────────────────────────────────────────────────────────

  Widget _emptyResult(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          '검색 결과가 없습니다.',
          style: TextStyle(fontSize: 15, color: Color(0xFF9E9E9E)),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 내부 헬퍼
// ─────────────────────────────────────────────────────────────

class _Grp<T> {
  final String header;
  final List<T> items;
  const _Grp(this.header, this.items);
}
